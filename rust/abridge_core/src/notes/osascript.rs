//! Runs the fixed Notes JXA script and maps its failures to Notes error codes.

use serde_json::Value;
use std::io::{ErrorKind, Read, Write};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use super::error::NotesError;
use super::script::{FOLDER_NOT_EMPTY, JXA_SCRIPT, NOTE_CHANGED, NOTE_IN_RECENTLY_DELETED};

const OSASCRIPT_TIMEOUT: Duration = Duration::from_secs(30);
const EXIT_POLL_STEP: Duration = Duration::from_millis(50);

pub(crate) const NOTE_IN_RECENTLY_DELETED_MESSAGE: &str = "the note is already in Recently Deleted; Notes erases it from there on its own, and permanent deletion is not available";

/// User input travels only inside `payload`, as JSON on the script's stdin.
pub(crate) fn run(payload: &Value) -> Result<Value, NotesError> {
  #[cfg(test)]
  if let Some(result) = invoke_test_runner(payload) {
    return result;
  }
  let json =
    serde_json::to_string(payload).map_err(|_| NotesError::new("notes_error", "failed to encode notes request"))?;
  let mut child = Command::new("/usr/bin/osascript")
    .args(["-l", "JavaScript", "-e", JXA_SCRIPT])
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .map_err(map_spawn)?;
  let mut stdin = child
    .stdin
    .take()
    .ok_or_else(|| NotesError::new("notes_error", "osascript stdin was not available"))?;
  let stdout = child.stdout.take();
  let stderr = child.stderr.take();
  // A note body can be larger than the pipe buffer. Write it off this thread, and drain both
  // outputs at the same time, so neither side blocks the other.
  let writer = thread::spawn(move || {
    let result = stdin.write_all(json.as_bytes()).and_then(|_| stdin.flush());
    drop(stdin);
    result
  });
  let stdout_thread = thread::spawn(move || read_pipe(stdout));
  let stderr_thread = thread::spawn(move || read_pipe(stderr));
  let deadline = Instant::now() + OSASCRIPT_TIMEOUT;
  let status = loop {
    match child.try_wait() {
      Ok(Some(status)) => break status,
      Ok(None) if Instant::now() >= deadline => {
        let _ = child.kill();
        let _ = child.wait();
        let _ = writer.join();
        let _ = stdout_thread.join();
        let _ = stderr_thread.join();
        return Err(timed_out());
      }
      Ok(None) => thread::sleep(EXIT_POLL_STEP),
      Err(err) => {
        let _ = child.kill();
        let _ = writer.join();
        let _ = stdout_thread.join();
        let _ = stderr_thread.join();
        return Err(NotesError::new("notes_error", format!("osascript failed: {err}")));
      }
    }
  };
  // BrokenPipe means the script exited before reading a trailing byte. The exit status is the
  // outcome; a write error before that is not.
  if let Err(err) = writer
    .join()
    .unwrap_or_else(|_| Err(std::io::Error::other("stdin writer panicked")))
    && err.kind() != ErrorKind::BrokenPipe
  {
    let _ = stdout_thread.join();
    let _ = stderr_thread.join();
    return Err(map_spawn(err));
  }
  let stdout = stdout_thread.join().unwrap_or_default();
  let stderr = stderr_thread.join().unwrap_or_default();
  if status.success() {
    return serde_json::from_str(stdout.trim())
      .map_err(|_| NotesError::new("notes_error", "osascript returned invalid JSON"));
  }
  Err(map_failure(&stderr))
}

fn map_spawn(err: std::io::Error) -> NotesError {
  if err.kind() == ErrorKind::ArgumentListTooLong {
    return NotesError::new("body_too_large", "the note body is too large to send to Notes");
  }
  NotesError::new("notes_error", format!("failed to start osascript: {err}"))
}

/// Killing osascript does not undo an Apple event Notes may already be applying.
fn timed_out() -> NotesError {
  NotesError::new(
    "write_unconfirmed",
    "osascript timed out. The change may have happened; check before retrying",
  )
}

pub(crate) fn map_failure(stderr: &str) -> NotesError {
  if stderr.contains(NOTE_IN_RECENTLY_DELETED) {
    return NotesError::new("note_in_recently_deleted", NOTE_IN_RECENTLY_DELETED_MESSAGE);
  }
  if stderr.contains(NOTE_CHANGED) {
    return NotesError::new(
      "note_changed",
      "the note changed since it was read; nothing was written. Read it again and retry",
    );
  }
  if stderr.contains(FOLDER_NOT_EMPTY) {
    return NotesError::new(
      "folder_not_empty",
      "the folder still holds notes or subfolders; move or delete those first",
    );
  }
  let message = bounded_message(stderr);
  if stderr.contains("-1743") {
    NotesError::new("automation_denied", message)
  } else if stderr.contains("Duplicate folder name") {
    NotesError::new("folder_name_taken", message)
  } else {
    NotesError::new("notes_error", message)
  }
}

fn read_pipe(pipe: Option<impl Read>) -> String {
  let mut output = String::new();
  if let Some(mut pipe) = pipe {
    let _ = pipe.read_to_string(&mut output);
  }
  output
}

fn bounded_message(stderr: &str) -> String {
  let trimmed = stderr.trim();
  if trimmed.is_empty() {
    "osascript failed".to_string()
  } else {
    trimmed.chars().take(500).collect()
  }
}

#[cfg(test)]
type TestRunner = Box<dyn Fn(&Value) -> Result<Value, NotesError> + Send>;

#[cfg(test)]
thread_local! {
  static RUNNER: std::cell::RefCell<Option<TestRunner>> = const { std::cell::RefCell::new(None) };
}

#[cfg(test)]
fn invoke_test_runner(payload: &Value) -> Option<Result<Value, NotesError>> {
  RUNNER.with(|slot| {
    let borrowed = slot.borrow();
    borrowed.as_ref().map(|runner| runner(payload))
  })
}

/// Replaces `run` on this thread until dropped. Tests must not call the real Notes app.
#[cfg(test)]
pub(crate) struct RunnerGuard;

#[cfg(test)]
impl Drop for RunnerGuard {
  fn drop(&mut self) {
    RUNNER.with(|slot| *slot.borrow_mut() = None);
  }
}

#[cfg(test)]
pub(crate) fn set_runner_for_test(
  runner: impl Fn(&Value) -> Result<Value, NotesError> + Send + 'static,
) -> RunnerGuard {
  RUNNER.with(|slot| *slot.borrow_mut() = Some(Box::new(runner)));
  RunnerGuard
}

#[cfg(test)]
mod tests {
  use super::{map_failure, timed_out};

  #[test]
  fn maps_osascript_errors_to_notes_codes() {
    let denied = map_failure("execution error: Not authorized to send Apple events to Notes. (-1743)\n");
    assert_eq!(denied.code, "automation_denied");
    assert_eq!(
      denied.message,
      "execution error: Not authorized to send Apple events to Notes. (-1743)"
    );
    let taken = map_failure("execution error: Error: Error: Duplicate folder name. (-10000)");
    assert_eq!(taken.code, "folder_name_taken");
    let trashed = map_failure("execution error: Error: ABRIDGE_NOTE_IN_RECENTLY_DELETED (-2700)");
    assert_eq!(trashed.code, "note_in_recently_deleted");
    let other = map_failure("  execution error: something bad\n");
    assert_eq!(other.code, "notes_error");
    assert_eq!(other.message, "execution error: something bad");
    assert_eq!(map_failure("   ").message, "osascript failed");
    let changed = map_failure("execution error: Error: ABRIDGE_NOTE_CHANGED (-2700)");
    assert_eq!(changed.code, "note_changed");
    assert!(changed.message.contains("nothing was written"));
    let populated = map_failure("execution error: Error: ABRIDGE_FOLDER_NOT_EMPTY (-2700)");
    assert_eq!(populated.code, "folder_not_empty");
    assert!(populated.message.contains("notes or subfolders"));
  }

  #[test]
  fn timeout_is_outcome_unknown() {
    let err = timed_out();
    assert_eq!(err.code, "write_unconfirmed");
    assert!(err.message.contains("may have happened"));
    assert!(err.message.contains("check before retrying"));
  }

  #[test]
  fn argument_list_too_long_is_body_too_large() {
    let err = super::map_spawn(std::io::Error::new(
      std::io::ErrorKind::ArgumentListTooLong,
      "arg list too long",
    ));
    assert_eq!(err.code, "body_too_large");
    let other = super::map_spawn(std::io::Error::other("nope"));
    assert_eq!(other.code, "notes_error");
  }
}
