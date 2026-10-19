//! Core Data and Unix timestamps as RFC 3339 UTC strings.

const CORE_DATA_EPOCH_OFFSET: f64 = 978_307_200.0;

pub(crate) fn core_data_to_rfc3339(seconds_since_2001: f64) -> Option<String> {
  unix_to_rfc3339(seconds_since_2001 + CORE_DATA_EPOCH_OFFSET)
}

pub(crate) fn unix_secs_to_rfc3339(seconds: i64) -> Option<String> {
  unix_to_rfc3339(seconds as f64)
}

/// 0001-01-01T00:00:00Z through 9999-12-31T23:59:59Z, the range RFC 3339 years can express.
const MIN_UNIX_SECONDS: f64 = -62_135_596_800.0;
const MAX_UNIX_SECONDS: f64 = 253_402_300_799.0;

pub(crate) fn unix_to_rfc3339(seconds: f64) -> Option<String> {
  if !(MIN_UNIX_SECONDS..=MAX_UNIX_SECONDS).contains(&seconds) {
    return None;
  }
  let mut whole = seconds.floor() as i64;
  let mut millis = ((seconds - whole as f64) * 1000.0).round() as i64;
  if millis >= 1000 {
    whole = whole.checked_add(1)?;
    millis = 0;
  }
  if millis < 0 {
    return None;
  }
  let days = whole.div_euclid(86_400);
  let date = crate::datetime::date_from_unix_days(days)?;
  let year = u32::try_from(date.year()).ok()?;
  let month = u32::from(date.month().unsigned_abs());
  let day = u32::from(date.day().unsigned_abs());
  if year > 9999 {
    return None;
  }
  let time_of_day = whole.rem_euclid(86_400) as u32;
  let hour = time_of_day / 3600;
  let minute = (time_of_day % 3600) / 60;
  let second = time_of_day % 60;
  if millis == 0 {
    Some(format!(
      "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z"
    ))
  } else {
    Some(format!(
      "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z"
    ))
  }
}

#[cfg(test)]
mod tests {
  use super::{core_data_to_rfc3339, unix_secs_to_rfc3339, unix_to_rfc3339};

  #[test]
  fn formats_unix_and_core_data_epochs() {
    assert_eq!(unix_to_rfc3339(0.0).as_deref(), Some("1970-01-01T00:00:00Z"));
    assert_eq!(unix_secs_to_rfc3339(0).as_deref(), Some("1970-01-01T00:00:00Z"));
    assert_eq!(core_data_to_rfc3339(0.0).as_deref(), Some("2001-01-01T00:00:00Z"));
    assert_eq!(core_data_to_rfc3339(86_400.0).as_deref(), Some("2001-01-02T00:00:00Z"));
    assert_eq!(unix_to_rfc3339(0.5).as_deref(), Some("1970-01-01T00:00:00.500Z"));
  }

  #[test]
  fn rejects_timestamps_outside_rfc3339_years() {
    assert_eq!(unix_to_rfc3339(1e20), None);
    assert_eq!(unix_to_rfc3339(-1e20), None);
    assert_eq!(unix_to_rfc3339(f64::NAN), None);
    assert_eq!(core_data_to_rfc3339(f64::MAX), None);
    assert_eq!(
      unix_to_rfc3339(253_402_300_799.0).as_deref(),
      Some("9999-12-31T23:59:59Z")
    );
  }
}
