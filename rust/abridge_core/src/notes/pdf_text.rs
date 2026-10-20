//! Repairs letter-spaced PDF extraction using the page's own encoded text strings.
//!
//! Core Text may kern every glyph in a TJ array. The layout extractor can mistake those
//! adjustments for word spaces. Literal strings retain the real spaces, including across font
//! switches. Replace only suspect lines whose non-whitespace text agrees exactly.

use lopdf::{Document, Encoding, Object, content::Content};

const MAX_PDF_BYTES: usize = 32 * 1024 * 1024;
const MAX_PAGE_BYTES: usize = 1024 * 1024;
const MAX_TEXT_BYTES: usize = 4 * 1024 * 1024;

pub(super) fn repair_tracked_markdown(markdown: &str, pdf: &[u8]) -> String {
  if pdf.len() > MAX_PDF_BYTES || !markdown.lines().any(looks_tracked) {
    return markdown.to_string();
  }
  let Some(literals) = literal_lines(pdf) else {
    return markdown.to_string();
  };
  let replacements: std::collections::HashMap<String, &str> = literals
    .lines()
    .filter(|line| !line.trim().is_empty())
    .map(|line| (match_key(line), line.trim()))
    .collect();
  let mut out = String::with_capacity(markdown.len());
  for (index, line) in markdown.lines().enumerate() {
    if index > 0 {
      out.push('\n');
    }
    let replacement = looks_tracked(line)
      .then(|| replacements.get(&match_key(line)))
      .flatten();
    out.push_str(replacement.copied().unwrap_or(line));
  }
  if markdown.ends_with('\n') {
    out.push('\n');
  }
  out
}

fn looks_tracked(line: &str) -> bool {
  let mut count = 0;
  let mut singles = 0;
  let mut letters = 0;
  for token in line.trim().trim_start_matches('#').split_whitespace() {
    count += 1;
    let mut chars = token.chars();
    if let Some(character) = chars.next()
      && chars.next().is_none()
    {
      singles += 1;
      letters += usize::from(character.is_alphanumeric());
    }
  }
  count >= 6 && letters >= 4 && singles * 2 >= count
}

fn match_key(line: &str) -> String {
  line
    .trim()
    .trim_start_matches('#')
    .chars()
    .filter(|character| !character.is_whitespace())
    .collect()
}

fn newline(text: &mut String) {
  if !text.is_empty() && !text.ends_with('\n') {
    text.push('\n');
  }
}

fn literal_lines(pdf: &[u8]) -> Option<String> {
  let document = Document::load_mem(pdf).ok()?;
  let mut text = String::new();
  for page in document.get_pages().values() {
    let fonts = document.get_page_fonts(*page).ok()?;
    let mut encodings = std::collections::BTreeMap::new();
    for (name, font) in fonts {
      let encoding = font.get_font_encoding_with_limit(&document, MAX_PAGE_BYTES).ok()?;
      encodings.insert(name, encoding);
    }
    let data = document.get_page_content_with_limit(*page, MAX_PAGE_BYTES).ok()?;
    let content = Content::decode(&data).ok()?;
    let mut encoding = None;
    for operation in content.operations {
      match operation.operator.as_str() {
        "Tf" => {
          encoding = operation
            .operands
            .first()
            .and_then(|operand| operand.as_name().ok())
            .and_then(|name| encodings.get(name));
        }
        "Tj" | "TJ" => {
          append_strings(&mut text, encoding?, operation.operands.first()?)?;
        }
        "'" | "\"" => {
          newline(&mut text);
          append_strings(&mut text, encoding?, operation.operands.last()?)?;
        }
        "BT" | "ET" | "T*" | "Tm" => newline(&mut text),
        "Td" | "TD" => {
          let vertical = operation
            .operands
            .get(1)
            .and_then(|value| value.as_float().ok())
            .unwrap_or(0.0);
          if vertical != 0.0 {
            newline(&mut text);
          }
        }
        _ => {}
      }
      if text.len() > MAX_TEXT_BYTES {
        return None;
      }
    }
    newline(&mut text);
  }
  Some(text)
}

fn append_strings(text: &mut String, encoding: &Encoding<'_>, operand: &Object) -> Option<()> {
  match operand {
    Object::String(bytes, _) => encoding.write_to_string(bytes, text).ok()?,
    Object::Array(items) => {
      for item in items {
        if let Object::String(bytes, _) = item {
          encoding.write_to_string(bytes, text).ok()?;
        }
      }
    }
    _ => {}
  }
  Some(())
}

#[cfg(test)]
mod tests {
  use super::repair_tracked_markdown;

  fn pdf(objects: &[Vec<u8>]) -> Vec<u8> {
    let mut out = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::new();
    for (index, object) in objects.iter().enumerate() {
      offsets.push(out.len());
      out.extend(format!("{} 0 obj\n", index + 1).into_bytes());
      out.extend(object);
      out.extend(b"\nendobj\n");
    }
    let xref = out.len();
    out.extend(format!("xref\n0 {}\n", objects.len() + 1).into_bytes());
    out.extend(b"0000000000 65535 f \n");
    for offset in offsets {
      out.extend(format!("{offset:010} 00000 n \n").into_bytes());
    }
    out.extend(
      format!(
        "trailer << /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
        objects.len() + 1
      )
      .into_bytes(),
    );
    out
  }

  fn stream_object(data: &[u8], filter: &str) -> Vec<u8> {
    let mut object = format!("<< /Length {}{filter} >>\nstream\n", data.len()).into_bytes();
    object.extend(data);
    object.extend(b"\nendstream");
    object
  }

  // Core Text's glyph-by-glyph TJ sequence, including a font switch for the dollar sign.
  fn tracked_amount() -> Vec<u8> {
    use flate2::{Compression, write::ZlibEncoder};
    use std::io::Write;
    let stream = b"BT -0.1274 Tc 22 0 0 22 72 611 Tm /F1 1 Tf [ (To) -116 (t) -110 (a) -116 (l) -116 ( ) -116 (d) -115 (u) -115 (e) -116 (:) -116 ( ) -116 ] TJ /F2 1 Tf [ (!) -115 ] TJ /F1 1 Tf [ (1) -116 (2) -116 (8) -92 (.) -103 (4) -116 (0) ] TJ ET\n";
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(stream).expect("deflate");
    let compressed = encoder.finish().expect("deflate");
    let cmap = b"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<00><FF>\nendcodespacerange\n1 beginbfrange\n<21><21><0024>\nendbfrange\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n";
    pdf(&[
      b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
      b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_vec(),
      b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>".to_vec(),
      stream_object(&compressed, " /Filter /FlateDecode"),
      b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /MacRomanEncoding >>".to_vec(),
      b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 7 0 R >>".to_vec(),
      stream_object(cmap, ""),
    ])
  }

  #[test]
  fn tracked_glyphs_preserve_words_and_font_mappings() {
    for bytes in [tracked_amount().as_slice(), include_bytes!("quartz_total_due.pdf")] {
      let markdown = anydoc::to_markdown_bytes(bytes, anydoc::Format::Pdf).expect("markdown");
      assert!(
        markdown.lines().any(super::looks_tracked),
        "fixture no longer letter-spaces: {markdown}"
      );
      let text = repair_tracked_markdown(&markdown, bytes);
      assert!(
        text.contains("Total due: $128.40"),
        "{text}; literal: {:?}",
        super::literal_lines(bytes)
      );
      assert!(!text.lines().any(super::looks_tracked), "{text}");
      assert!(!text.contains('!'), "{text}");
    }
  }

  #[test]
  fn unrecognized_or_untracked_text_is_unchanged() {
    let bytes = tracked_amount();
    assert_eq!(repair_tracked_markdown("I am a person.\n", &bytes), "I am a person.\n");
    assert_eq!(repair_tracked_markdown("A b c d e f g h", &bytes), "A b c d e f g h");
    assert_eq!(
      repair_tracked_markdown("T o t a l d u e", b"%PDF broken"),
      "T o t a l d u e"
    );
  }

  #[test]
  fn attachment_and_search_read_the_repaired_document_line() {
    use crate::notes::{attachment_fixture::attachment_store, call_output, call_with_store};
    use serde_json::json;
    let (_dir, store) = attachment_store();
    let conn = rusqlite::Connection::open(&store).expect("db");
    conn
      .execute_batch(
        "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = 'invoice.pdf' WHERE ZIDENTIFIER = 'media-1';
      UPDATE ZICCLOUDSYNCINGOBJECT SET ZTYPEUTI = 'com.adobe.pdf', ZTITLE = 'invoice.pdf' WHERE ZIDENTIFIER = 'att-1';",
      )
      .expect("pdf rows");
    drop(conn);
    let file = store
      .parent()
      .expect("dir")
      .join("Accounts/acct-1/Media/media-1/invoice.pdf");
    std::fs::write(file, include_bytes!("quartz_total_due.pdf")).expect("pdf");
    let attachment =
      call_output(&store, "get_attachment", &json!({"attachment_identifier": "att-1"})).expect("attachment");
    assert!(
      attachment.payload["content"]
        .as_str()
        .expect("content")
        .contains("Total due: $128.40")
    );
    let hits = call_with_store(&store, "search_notes", &json!({"query": "'128.40"})).expect("search");
    assert_eq!(hits[0]["identifier"], "note-i");
    assert_eq!(hits[0]["matches"][0]["field"], "attachment: att-1 invoice.pdf");
    assert_eq!(hits[0]["matches"][0]["excerpt"], "invoice.pdf\nTotal due: $«128.40»");
  }

  #[cfg(target_os = "macos")]
  #[test]
  fn cupsfilter_text_keeps_its_words() {
    let (_dir, store) = crate::notes::attachment_fixture::attachment_store();
    let source = store.with_file_name("due.txt");
    std::fs::write(&source, "Total due: $128.40\n").expect("txt");
    let output = std::process::Command::new("/usr/sbin/cupsfilter")
      .args(["-i", "text/plain", "-m", "application/pdf"])
      .arg(source)
      .output()
      .expect("cupsfilter");
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let markdown = anydoc::to_markdown_bytes(&output.stdout, anydoc::Format::Pdf).expect("markdown");
    let text = repair_tracked_markdown(&markdown, &output.stdout);
    assert!(text.contains("Total due: $128.40"), "{text}");
  }
}
