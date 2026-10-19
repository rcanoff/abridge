//! Directories and files created without following symlinks.
//!
//! The last path component is never followed. A symlink is unlinked as a directory entry; its
//! target is left untouched. Callers that need a file to disappear on drop use [`ScratchDir`].

use std::ffi::{CStr, CString};
use std::fs::{DirBuilder, File, OpenOptions};
use std::io::{self, ErrorKind, Read};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

#[cfg(target_os = "macos")]
mod flags {
  pub const O_DIRECTORY: i32 = 0x0010_0000;
  pub const O_NOFOLLOW: i32 = 0x0000_0100;
  pub const O_CLOEXEC: i32 = 0x0100_0000;
  pub const O_CREAT: i32 = 0x0000_0200;
  pub const O_EXCL: i32 = 0x0000_0800;
  pub const O_NONBLOCK: i32 = 0x0000_0004;
  pub const AT_REMOVEDIR: i32 = 0x0080;
  pub const D_TYPE: usize = 20;
  pub const D_NAME: usize = 21;
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod flags {
  pub const O_DIRECTORY: i32 = 0x1_0000;
  pub const O_NOFOLLOW: i32 = 0x2_0000;
  pub const O_CLOEXEC: i32 = 0x8_0000;
  pub const O_CREAT: i32 = 64;
  pub const O_EXCL: i32 = 128;
  pub const O_NONBLOCK: i32 = 2048;
  pub const AT_REMOVEDIR: i32 = 0x200;
  pub const D_TYPE: usize = 18;
  pub const D_NAME: usize = 19;
}

#[cfg(all(target_os = "linux", target_arch = "aarch64"))]
mod flags {
  pub const O_DIRECTORY: i32 = 0x4000;
  pub const O_NOFOLLOW: i32 = 0x8000;
  pub const O_CLOEXEC: i32 = 0x8_0000;
  pub const O_CREAT: i32 = 64;
  pub const O_EXCL: i32 = 128;
  pub const O_NONBLOCK: i32 = 2048;
  pub const AT_REMOVEDIR: i32 = 0x200;
  pub const D_TYPE: usize = 18;
  pub const D_NAME: usize = 19;
}

const O_RDONLY: i32 = 0;
const O_WRONLY: i32 = 1;
#[cfg(target_os = "macos")]
const ELOOP: i32 = 62;
#[cfg(target_os = "linux")]
const ELOOP: i32 = 40;
const ENOTDIR: i32 = 20;
const EISDIR: i32 = 21;
const DT_UNKNOWN: u8 = 0;
const DT_DIR: u8 = 4;
const DT_REG: u8 = 8;
const DT_LNK: u8 = 10;
const CREATE_ATTEMPTS: u32 = 4;
const REMOVE_DEPTH: u32 = 32;

unsafe extern "C" {
  fn openat(dirfd: i32, path: *const i8, flags: i32, mode: i32) -> i32;
  fn mkdirat(dirfd: i32, path: *const i8, mode: u32) -> i32;
  fn unlinkat(dirfd: i32, path: *const i8, flags: i32) -> i32;
  fn close(fd: i32) -> i32;
  fn dup(fd: i32) -> i32;
  fn fdopendir(fd: i32) -> *mut std::ffi::c_void;
  fn readdir(dirp: *mut std::ffi::c_void) -> *mut std::ffi::c_void;
  fn closedir(dirp: *mut std::ffi::c_void) -> i32;
  #[cfg(target_os = "macos")]
  fn __error() -> *mut i32;
  #[cfg(target_os = "linux")]
  fn __errno_location() -> *mut i32;
}

fn clear_errno() {
  // Safety: the process errno cell is valid for the calling thread.
  unsafe {
    #[cfg(target_os = "macos")]
    {
      *__error() = 0;
    }
    #[cfg(target_os = "linux")]
    {
      *__errno_location() = 0;
    }
  }
}

fn errno_value() -> i32 {
  // Safety: the process errno cell is valid for the calling thread.
  unsafe {
    #[cfg(target_os = "macos")]
    {
      *__error()
    }
    #[cfg(target_os = "linux")]
    {
      *__errno_location()
    }
  }
}

fn cvt(result: i32) -> io::Result<i32> {
  if result < 0 {
    Err(io::Error::last_os_error())
  } else {
    Ok(result)
  }
}

fn c_name(name: &str) -> io::Result<CString> {
  if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\0') {
    return Err(io::Error::new(ErrorKind::InvalidInput, "refusing path component"));
  }
  CString::new(name).map_err(|_| io::Error::new(ErrorKind::InvalidInput, "name contains a nul"))
}

fn set_mode(file: &File, mode: u32) -> io::Result<()> {
  let mut permissions = file.metadata()?.permissions();
  permissions.set_mode(mode);
  file.set_permissions(permissions)
}

/// Open `path` following symlinks, then require the final target to be a regular file.
/// A FIFO or device is rejected before a blocking read (`O_NONBLOCK` on the open).
pub(crate) fn open_regular(path: &Path) -> io::Result<File> {
  let mut options = OpenOptions::new();
  options.read(true);
  // `O_NONBLOCK` so a FIFO or device does not wait for a writer. The final target is checked below.
  options.custom_flags(flags::O_NONBLOCK | flags::O_CLOEXEC);
  let file = options.open(path)?;
  if file.metadata()?.is_file() {
    Ok(file)
  } else {
    Err(io::Error::new(ErrorKind::InvalidInput, "not a regular file"))
  }
}

/// A directory fd opened with `O_NOFOLLOW | O_DIRECTORY`. Drop closes the fd and leaves the
/// directory on disk.
pub(crate) struct OpenDir {
  file: File,
  path: PathBuf,
}

impl OpenDir {
  /// Open an existing real directory, or create it mode 0700. A symlink or non-directory is an error.
  pub(crate) fn establish(path: &Path) -> io::Result<Self> {
    match open_dir_nofollow(path) {
      Ok(file) => {
        set_mode(&file, 0o700)?;
        Ok(Self {
          file,
          path: path.to_path_buf(),
        })
      }
      Err(err) if err.kind() == ErrorKind::NotFound => {
        let mut builder = DirBuilder::new();
        builder.mode(0o700);
        match builder.create(path) {
          Ok(()) => {}
          Err(err) if err.kind() == ErrorKind::AlreadyExists => {}
          Err(err) => return Err(err),
        }
        let file = open_dir_nofollow(path)?;
        set_mode(&file, 0o700)?;
        Ok(Self {
          file,
          path: path.to_path_buf(),
        })
      }
      Err(err) => Err(err),
    }
  }

  /// `parent/<prefix>-<random>` mode 0700. The name is not predictable and the open does not follow
  /// a symlink planted in its place.
  pub(crate) fn create_unique(parent: &Path, prefix: &str) -> io::Result<Self> {
    for _ in 0..16 {
      let path = parent.join(format!("{prefix}-{}", random_hex()?));
      let mut builder = DirBuilder::new();
      builder.mode(0o700);
      match builder.create(&path) {
        Ok(()) => {}
        Err(err) if err.kind() == ErrorKind::AlreadyExists => continue,
        Err(err) => return Err(err),
      }
      match open_dir_nofollow(&path) {
        Ok(file) => {
          set_mode(&file, 0o700)?;
          return Ok(Self { file, path });
        }
        Err(err) if is_loop(&err) => continue,
        Err(err) => return Err(err),
      }
    }
    Err(io::Error::new(
      ErrorKind::AlreadyExists,
      "could not create a private directory",
    ))
  }

  #[cfg(test)]
  pub(crate) fn path(&self) -> &Path {
    &self.path
  }

  /// Open or create `name` as a real subdirectory (0700). A symlink or other non-directory entry
  /// is unlinked (the entry only) and replaced.
  pub(crate) fn ensure_child(&self, name: &str) -> io::Result<Self> {
    let name_c = c_name(name)?;
    for _ in 0..CREATE_ATTEMPTS {
      match open_child(&self.file, &name_c) {
        Ok(file) => {
          set_mode(&file, 0o700)?;
          return Ok(Self {
            file,
            path: self.path.join(name),
          });
        }
        Err(err) if err.kind() == ErrorKind::NotFound => match mkdir_child(&self.file, &name_c) {
          Ok(()) => continue,
          Err(err) if err.kind() == ErrorKind::AlreadyExists => continue,
          Err(err) => return Err(err),
        },
        Err(err) if is_replaceable(&err) => {
          unlink_entry(&self.file, &name_c, false)?;
          continue;
        }
        Err(err) => return Err(err),
      }
    }
    Err(io::Error::new(
      ErrorKind::AlreadyExists,
      "could not create a private directory",
    ))
  }

  /// Copy `source` to `name` (0600). An existing symlink is unlinked and not followed; the new
  /// file is created with `O_EXCL | O_NOFOLLOW`.
  pub(crate) fn write_file(&self, name: &str, source: &Path) -> io::Result<PathBuf> {
    let mut input = File::open(source)?;
    self.write_reader(name, &mut input)
  }

  pub(crate) fn write_bytes(&self, name: &str, bytes: &[u8]) -> io::Result<PathBuf> {
    self.write_reader(name, &mut io::Cursor::new(bytes))
  }

  /// Read `name` without following a symlink, and refuse anything that is not a regular file
  /// or that is larger than `limit`.
  pub(crate) fn read_file(&self, name: &str, limit: u64) -> io::Result<Vec<u8>> {
    let name_c = c_name(name)?;
    let file = open_nofollow_file(&self.file, &name_c)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() || metadata.len() > limit {
      return Err(io::Error::new(
        ErrorKind::InvalidInput,
        "not a regular file within the limit",
      ));
    }
    let mut bytes = Vec::new();
    file.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
      return Err(io::Error::new(ErrorKind::InvalidInput, "file grew past the limit"));
    }
    Ok(bytes)
  }

  fn write_reader(&self, name: &str, input: &mut impl Read) -> io::Result<PathBuf> {
    let name_c = c_name(name)?;
    for _ in 0..CREATE_ATTEMPTS {
      match create_exclusive(&self.file, &name_c) {
        Ok(mut file) => {
          set_mode(&file, 0o600)?;
          io::copy(input, &mut file)?;
          return Ok(self.path.join(name));
        }
        Err(err) if err.kind() == ErrorKind::AlreadyExists || is_loop(&err) => {
          unlink_entry(&self.file, &name_c, false)?;
        }
        Err(err) if is_dir_error(&err) => {
          if let Ok(child) = open_child(&self.file, &name_c) {
            let nested = Self {
              file: child,
              path: self.path.join(name),
            };
            nested.remove_children(0)?;
          }
          unlink_entry(&self.file, &name_c, true)?;
        }
        Err(err) => return Err(err),
      }
    }
    Err(io::Error::new(
      ErrorKind::AlreadyExists,
      "could not create a private file",
    ))
  }

  /// Delete direct children older than `ttl`. Symlinks and special files are unlinked without
  /// being opened. Directory trees are removed without following links.
  pub(crate) fn remove_older_than(&self, ttl: Duration) {
    let Some(cutoff) = SystemTime::now().checked_sub(ttl) else {
      return;
    };
    let Ok(entries) = list_dir(&self.file) else {
      return;
    };
    for (name, kind) in entries {
      match kind {
        Kind::Symlink | Kind::Other => {
          let _ = unlink_entry(&self.file, &name, false);
        }
        Kind::File => {
          if modified_before(&self.file, &name, false, cutoff) {
            let _ = unlink_entry(&self.file, &name, false);
          }
        }
        Kind::Dir => {
          if modified_before(&self.file, &name, true, cutoff) {
            if let Ok(child) = open_child(&self.file, &name) {
              let nested = Self {
                file: child,
                path: PathBuf::new(),
              };
              let _ = nested.remove_children(0);
            }
            let _ = unlink_entry(&self.file, &name, true);
          }
        }
      }
    }
  }

  fn remove_children(&self, depth: u32) -> io::Result<()> {
    if depth > REMOVE_DEPTH {
      return Ok(());
    }
    for (name, kind) in list_dir(&self.file)? {
      match kind {
        Kind::Dir => {
          if let Ok(child) = open_child(&self.file, &name) {
            let nested = Self {
              file: child,
              path: PathBuf::new(),
            };
            nested.remove_children(depth + 1)?;
          }
          unlink_entry(&self.file, &name, true)?;
        }
        Kind::File | Kind::Symlink | Kind::Other => unlink_entry(&self.file, &name, false)?,
      }
    }
    Ok(())
  }
}

/// Per-operation directory, removed on drop without following symlinks.
pub(crate) struct ScratchDir {
  dir: OpenDir,
}

impl ScratchDir {
  pub(crate) fn create() -> io::Result<Self> {
    Ok(Self {
      dir: OpenDir::create_unique(&std::env::temp_dir(), "abridge-rendition")?,
    })
  }

  #[cfg(test)]
  pub(crate) fn path(&self) -> &Path {
    self.dir.path()
  }

  pub(crate) fn write_bytes(&self, name: &str, bytes: &[u8]) -> io::Result<PathBuf> {
    self.dir.write_bytes(name, bytes)
  }

  pub(crate) fn read_file(&self, name: &str, limit: u64) -> io::Result<Vec<u8>> {
    self.dir.read_file(name, limit)
  }
}

impl Drop for ScratchDir {
  fn drop(&mut self) {
    let _ = self.dir.remove_children(0);
    let _ = std::fs::remove_dir(&self.dir.path);
  }
}

fn is_loop(err: &io::Error) -> bool {
  err.raw_os_error() == Some(ELOOP)
}

fn is_not_dir(err: &io::Error) -> bool {
  err.raw_os_error() == Some(ENOTDIR)
}

fn is_dir_error(err: &io::Error) -> bool {
  err.raw_os_error() == Some(EISDIR)
}

fn is_replaceable(err: &io::Error) -> bool {
  err.kind() == ErrorKind::AlreadyExists || is_loop(err) || is_not_dir(err) || is_dir_error(err)
}

fn open_dir_nofollow(path: &Path) -> io::Result<File> {
  let mut options = OpenOptions::new();
  options.read(true);
  // `O_NOFOLLOW` rejects a symlink at the final component. `O_DIRECTORY` rejects a non-directory.
  options.custom_flags(flags::O_DIRECTORY | flags::O_NOFOLLOW | flags::O_CLOEXEC);
  options.open(path)
}

fn open_child(dir: &File, name: &CStr) -> io::Result<File> {
  // Safety: `name` is a single path component. The new fd owns the directory inode, not a symlink.
  let fd = cvt(unsafe {
    openat(
      dir.as_raw_fd(),
      name.as_ptr(),
      O_RDONLY | flags::O_DIRECTORY | flags::O_NOFOLLOW | flags::O_CLOEXEC,
      0,
    )
  })?;
  Ok(unsafe { File::from_raw_fd(fd) })
}

fn mkdir_child(dir: &File, name: &CStr) -> io::Result<()> {
  // Safety: `name` is a single path component relative to `dir`.
  cvt(unsafe { mkdirat(dir.as_raw_fd(), name.as_ptr(), 0o700) }).map(|_| ())
}

fn create_exclusive(dir: &File, name: &CStr) -> io::Result<File> {
  // Safety: `O_EXCL | O_NOFOLLOW` creates a new inode or fails. It does not open a symlink target.
  let fd = cvt(unsafe {
    openat(
      dir.as_raw_fd(),
      name.as_ptr(),
      O_WRONLY | flags::O_CREAT | flags::O_EXCL | flags::O_NOFOLLOW | flags::O_CLOEXEC,
      0o600,
    )
  })?;
  Ok(unsafe { File::from_raw_fd(fd) })
}

fn unlink_entry(dir: &File, name: &CStr, directory: bool) -> io::Result<()> {
  let flags = if directory { flags::AT_REMOVEDIR } else { 0 };
  // Safety: `unlinkat` without following removes the directory entry. A symlink's target stays.
  cvt(unsafe { unlinkat(dir.as_raw_fd(), name.as_ptr(), flags) }).map(|_| ())
}

fn modified_before(dir: &File, name: &CStr, directory: bool, cutoff: SystemTime) -> bool {
  let flags = O_RDONLY | flags::O_NOFOLLOW | flags::O_NONBLOCK | flags::O_CLOEXEC;
  let flags = if directory { flags | flags::O_DIRECTORY } else { flags };
  // Safety: no-follow open of one component. The `File` owns the fd.
  let Ok(fd) = cvt(unsafe { openat(dir.as_raw_fd(), name.as_ptr(), flags, 0) }) else {
    return false;
  };
  let file = unsafe { File::from_raw_fd(fd) };
  file
    .metadata()
    .and_then(|metadata| metadata.modified())
    .is_ok_and(|modified| modified < cutoff)
}

#[derive(Clone, Copy)]
enum Kind {
  Dir,
  File,
  Symlink,
  Other,
}

fn list_raw(dir: &File) -> io::Result<Vec<(CString, u8)>> {
  // Safety: `dup` yields a new fd. `fdopendir` takes ownership of that dup on success.
  let fd = cvt(unsafe { dup(dir.as_raw_fd()) })?;
  let dirp = unsafe { fdopendir(fd) };
  if dirp.is_null() {
    unsafe { close(fd) };
    return Err(io::Error::last_os_error());
  }
  let mut entries = Vec::new();
  loop {
    clear_errno();
    let ent = unsafe { readdir(dirp) };
    if ent.is_null() {
      let err = errno_value();
      // Safety: `closedir` frees the DIR and closes the dup'd fd.
      unsafe { closedir(dirp) };
      if err != 0 {
        return Err(io::Error::from_raw_os_error(err));
      }
      return Ok(entries);
    }
    if let Some((name, dtype)) = unsafe { read_entry(ent.cast()) } {
      entries.push((name, dtype));
    }
  }
}

/// `entry` is a `dirent` from `readdir`, valid until the next call.
unsafe fn read_entry(entry: *const u8) -> Option<(CString, u8)> {
  // Safety: `entry` points at a live `dirent` from `readdir` for this call.
  let dtype = unsafe { *entry.add(flags::D_TYPE) };
  let name = unsafe { CStr::from_ptr(entry.add(flags::D_NAME).cast()) };
  let bytes = name.to_bytes();
  if bytes.is_empty() || bytes == b"." || bytes == b".." {
    return None;
  }
  Some((CString::from(name), dtype))
}

fn list_dir(dir: &File) -> io::Result<Vec<(CString, Kind)>> {
  Ok(
    list_raw(dir)?
      .into_iter()
      .map(|(name, dtype)| {
        let kind = classify(dir, &name, dtype);
        (name, kind)
      })
      .collect(),
  )
}

fn classify(dir: &File, name: &CStr, dtype: u8) -> Kind {
  match dtype {
    DT_DIR => Kind::Dir,
    DT_REG => Kind::File,
    DT_LNK => Kind::Symlink,
    DT_UNKNOWN => probe_kind(dir, name),
    _ => Kind::Other,
  }
}

fn probe_kind(dir: &File, name: &CStr) -> Kind {
  match open_child(dir, name) {
    Ok(_) => Kind::Dir,
    Err(err) if is_loop(&err) => Kind::Symlink,
    Err(err) if is_not_dir(&err) => match open_nofollow_file(dir, name) {
      Ok(file) if file.metadata().is_ok_and(|metadata| metadata.is_file()) => Kind::File,
      Ok(_) => Kind::Other,
      Err(err) if is_loop(&err) => Kind::Symlink,
      Err(_) => Kind::Other,
    },
    Err(_) => Kind::Other,
  }
}

fn open_nofollow_file(dir: &File, name: &CStr) -> io::Result<File> {
  // Safety: one component, no-follow, non-blocking so a FIFO open returns instead of waiting.
  let fd = cvt(unsafe {
    openat(
      dir.as_raw_fd(),
      name.as_ptr(),
      O_RDONLY | flags::O_NOFOLLOW | flags::O_NONBLOCK | flags::O_CLOEXEC,
      0,
    )
  })?;
  Ok(unsafe { File::from_raw_fd(fd) })
}

fn random_hex() -> io::Result<String> {
  let mut bytes = [0u8; 16];
  File::open("/dev/urandom")?.read_exact(&mut bytes)?;
  let mut hex = String::with_capacity(32);
  for byte in bytes {
    hex.push_str(&format!("{byte:02x}"));
  }
  Ok(hex)
}
