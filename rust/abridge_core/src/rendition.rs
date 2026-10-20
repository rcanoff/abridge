//! JPEG renditions, made with macOS `sips`, of images a model cannot take (Notes attachments,
//! contact photos): types models do not read (HEIC, TIFF, …) and images over the model image size
//! limit. The same ladder renders one page of a PDF. Also the shared size limits for image and file
//! content.

use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::private_dir::ScratchDir;

/// Image types MCP clients pass to models as images.
pub(crate) const MODEL_IMAGE_TYPES: [&str; 4] = ["image/jpeg", "image/png", "image/gif", "image/webp"];

/// Largest base64 image models accept (Anthropic's 5 MB limit).
pub(crate) const MODEL_IMAGE_MAX_BASE64: usize = 5 * 1024 * 1024;

/// Largest file whose base64 fits `MODEL_IMAGE_MAX_BASE64`.
const MODEL_IMAGE_MAX_BYTES: u64 = (MODEL_IMAGE_MAX_BASE64 / 4 * 3) as u64;

/// Largest file returned unmodified as an embedded resource. Base64 grows it by a third.
pub(crate) const MAX_RESOURCE_BYTES: u64 = 20 * 1024 * 1024;

/// Long edges tried in turn: 2048 px keeps scanned text legible; smaller sizes make the fit certain.
const LONG_EDGES: [u32; 4] = [2048, 1568, 1024, 768];
const JPEG_QUALITY: &str = "80";
const SIPS_TIMEOUT: Duration = Duration::from_secs(30);
const EXIT_POLL_STEP: Duration = Duration::from_millis(20);

pub(crate) fn needs_rendition(mime_type: &str, size: u64) -> bool {
  mime_type.starts_with("image/") && (!MODEL_IMAGE_TYPES.contains(&mime_type) || size > MODEL_IMAGE_MAX_BYTES)
}

/// A JPEG of `source` within the model image limit, or `None` when `sips` cannot make one.
pub(crate) fn jpeg_rendition(source: &Path) -> Option<Vec<u8>> {
  let scratch = ScratchDir::create().ok()?;
  render_in(&scratch, source)
}

/// One page of a PDF, rendered for a model.
pub(crate) enum PdfPage {
  Rendered {
    jpeg: Vec<u8>,
    page_count: u32,
  },
  OutOfRange {
    page_count: u32,
  },
  /// `lopdf` could not read the PDF (`page_count` is `None`), or `sips` could not render the page.
  Unrendered {
    page_count: Option<u32>,
  },
}

/// One page of a PDF, split out with `lopdf` and not rendered.
pub(crate) enum PdfSinglePage {
  /// PDF bytes of the requested page. `page_count` is the source document.
  Page {
    bytes: Vec<u8>,
    page_count: u32,
  },
  OutOfRange {
    page_count: u32,
  },
  /// `lopdf` could not read the PDF (`page_count` is `None`) or could not write the page.
  Unrendered {
    page_count: Option<u32>,
  },
}

/// Copies 1-based `page` into its own PDF. Callers that need pixels render the result; Vision text
/// sends these bytes so Swift can rasterize the page at full resolution.
pub(crate) fn pdf_single_page(pdf: &[u8], page: u32) -> PdfSinglePage {
  let Ok(mut document) = lopdf::Document::load_mem(pdf) else {
    return PdfSinglePage::Unrendered { page_count: None };
  };
  let page_count = u32::try_from(document.get_pages().len()).unwrap_or(u32::MAX);
  if page == 0 || page > page_count {
    return PdfSinglePage::OutOfRange { page_count };
  }
  let others: Vec<u32> = (1..=page_count).filter(|number| *number != page).collect();
  document.delete_pages(&others);
  document.prune_objects();
  let mut single = Vec::new();
  match document.save_to(&mut single) {
    Ok(()) => PdfSinglePage::Page {
      bytes: single,
      page_count,
    },
    Err(_) => PdfSinglePage::Unrendered {
      page_count: Some(page_count),
    },
  }
}

/// JPEG of one 1-based `page` of `pdf` within the model image limit. `sips` renders only a PDF's
/// first page, so the requested page is copied into a one-page PDF first.
pub(crate) fn jpeg_pdf_page(pdf: &[u8], page: u32) -> PdfPage {
  match pdf_single_page(pdf, page) {
    PdfSinglePage::Page { bytes, page_count } => match render_bytes("in.pdf", &bytes) {
      Some(jpeg) => PdfPage::Rendered { jpeg, page_count },
      None => PdfPage::Unrendered {
        page_count: Some(page_count),
      },
    },
    PdfSinglePage::OutOfRange { page_count } => PdfPage::OutOfRange { page_count },
    PdfSinglePage::Unrendered { page_count } => PdfPage::Unrendered { page_count },
  }
}

/// `jpeg_rendition` for image bytes held in memory (a contact photo, for example).
pub(crate) fn jpeg_rendition_of_bytes(bytes: &[u8]) -> Option<Vec<u8>> {
  render_bytes("in.img", bytes)
}

fn render_bytes(name: &str, bytes: &[u8]) -> Option<Vec<u8>> {
  let scratch = ScratchDir::create().ok()?;
  let input = scratch.write_bytes(name, bytes).ok()?;
  render_in(&scratch, &input)
}

fn render_in(scratch: &ScratchDir, source: &Path) -> Option<Vec<u8>> {
  let output = scratch.write_bytes("out.jpg", b"").ok()?;
  let jpeg = LONG_EDGES.iter().find_map(|&edge| {
    if !run_sips(source, &output, edge) {
      return None;
    }
    scratch.read_file("out.jpg", MODEL_IMAGE_MAX_BYTES).ok()
  });
  if jpeg.is_none() {
    tracing::debug!("sips could not make a JPEG rendition within the model image limit");
  }
  jpeg
}

fn run_sips(source: &Path, output: &Path, long_edge: u32) -> bool {
  let spawned = Command::new("/usr/bin/sips")
    .args(["-s", "format", "jpeg", "-s", "formatOptions", JPEG_QUALITY, "-Z"])
    .arg(long_edge.to_string())
    .arg(source)
    .arg("--out")
    .arg(output)
    .stdin(Stdio::null())
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn();
  let Ok(mut child) = spawned else {
    return false;
  };
  let deadline = Instant::now() + SIPS_TIMEOUT;
  loop {
    match child.try_wait() {
      Ok(Some(status)) => return status.success(),
      Ok(None) if Instant::now() >= deadline => {
        let _ = child.kill();
        let _ = child.wait();
        return false;
      }
      Ok(None) => thread::sleep(EXIT_POLL_STEP),
      Err(_) => return false,
    }
  }
}

#[cfg(test)]
mod tests {
  use super::{MODEL_IMAGE_MAX_BYTES, needs_rendition};

  #[test]
  fn renders_only_images_models_cannot_take() {
    assert!(!needs_rendition("image/jpeg", MODEL_IMAGE_MAX_BYTES));
    assert!(needs_rendition("image/jpeg", MODEL_IMAGE_MAX_BYTES + 1));
    assert!(needs_rendition("image/heic", 10));
    assert!(!needs_rendition("application/pdf", u64::MAX));
    assert!(!needs_rendition("video/quicktime", u64::MAX));
  }

  /// Runs the real `sips`: a 12 MB bitmap comes back as a JPEG within the model limit.
  #[cfg(target_os = "macos")]
  #[test]
  fn shrinks_a_large_bitmap_into_a_model_sized_jpeg() {
    let scratch = crate::private_dir::ScratchDir::create().expect("scratch");
    let source = scratch
      .write_bytes("in.bmp", &noisy_bitmap(2000, 2000))
      .expect("bitmap");
    let jpeg = super::jpeg_rendition(&source).expect("rendition");
    assert!(jpeg.starts_with(&[0xff, 0xd8, 0xff]));
    assert!(jpeg.len() as u64 <= MODEL_IMAGE_MAX_BYTES, "{} bytes", jpeg.len());
  }

  #[test]
  fn scratch_files_are_private_and_removed() {
    let scratch = crate::private_dir::ScratchDir::create().expect("scratch");
    let path = scratch.write_bytes("a.bin", b"hi").expect("file");
    assert_eq!(mode(&path), 0o600);
    assert_eq!(mode(scratch.path()), 0o700);
    let dir = scratch.path().to_path_buf();
    drop(scratch);
    assert!(!dir.exists());
  }

  #[test]
  fn rendition_does_not_follow_a_planted_output_symlink() {
    let dir = std::env::temp_dir().join(format!("abridge-rendition-plant-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("dir");
    let secret = dir.join("secret");
    std::fs::write(&secret, b"keep").expect("secret");
    let planted = std::env::temp_dir().join(format!("abridge-notes-rendition-{}-0.jpg", std::process::id()));
    let _ = std::fs::remove_file(&planted);
    std::os::unix::fs::symlink(&secret, &planted).expect("symlink");
    let _ = super::jpeg_rendition_of_bytes(b"not an image");
    assert_eq!(std::fs::read(&secret).expect("secret"), b"keep");
    let _ = std::fs::remove_file(&planted);
    let _ = std::fs::remove_dir_all(&dir);
  }

  fn mode(path: &std::path::Path) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    std::fs::symlink_metadata(path).expect("metadata").permissions().mode() & 0o777
  }

  /// An uncompressed 24-bit BMP of pseudo-random pixels, which JPEG cannot shrink much.
  #[cfg(target_os = "macos")]
  fn noisy_bitmap(width: u32, height: u32) -> Vec<u8> {
    let row = (width * 3).div_ceil(4) * 4;
    let pixels = row * height;
    let mut bytes = Vec::with_capacity(54 + pixels as usize);
    bytes.extend_from_slice(b"BM");
    for value in [54 + pixels, 0, 54, 40] {
      bytes.extend_from_slice(&value.to_le_bytes());
    }
    bytes.extend_from_slice(&(width as i32).to_le_bytes());
    bytes.extend_from_slice(&(height as i32).to_le_bytes());
    bytes.extend_from_slice(&1u16.to_le_bytes());
    bytes.extend_from_slice(&24u16.to_le_bytes());
    for value in [0, pixels, 2835, 2835, 0, 0] {
      bytes.extend_from_slice(&value.to_le_bytes());
    }
    let mut state = 0x2545_f491_u32;
    for _ in 0..pixels {
      state ^= state << 13;
      state ^= state >> 17;
      state ^= state << 5;
      bytes.push(state as u8);
    }
    bytes
  }
}
