//! One civil-time policy for tool arguments and agent-facing clocks.
//!
//! Instants are strict RFC 3339 (`T`/`t`, `Z`/`z` or `±HH:MM`, real Gregorian days).
//! Wall times are resolved with the system time zone database (`jiff`), which applies
//! POSIX rules after the last explicit TZif transition. A daylight-saving gap or fold
//! is an error: the server zone is never used to guess a timed instant.

use jiff::civil::{Date, DateTime, Time};
use jiff::tz::{AmbiguousOffset, Offset, TimeZone};
use jiff::{Span, Timestamp};

#[derive(Debug)]
pub(crate) enum EventDateInput {
  Offset,
  DateOnly(Date),
  Wall(DateTime),
}

#[derive(Debug)]
pub(crate) enum DateError {
  Invalid,
  ImpossibleDate,
  UnknownZone,
  Gap {
    wall: String,
    zone: String,
    before: String,
    after: String,
  },
  Fold {
    wall: String,
    zone: String,
    before: String,
    after: String,
  },
}

pub(crate) fn explain(key: &str, error: &DateError) -> String {
  match error {
    DateError::Invalid => format!(
      "$: {key} needs a numeric offset (Z or ±HH:MM) or time_zone. A time with neither is not read in the server's time zone"
    ),
    DateError::ImpossibleDate => format!("$: {key} is not a valid calendar date"),
    DateError::UnknownZone => {
      format!("$: time_zone must be a known IANA time zone so {key} is not read in the server's time zone")
    }
    DateError::Gap {
      wall,
      zone,
      before,
      after,
    } => format!("$: {key} {wall} does not exist in {zone} (daylight-saving gap from {before} to {after})"),
    DateError::Fold {
      wall,
      zone,
      before,
      after,
    } => {
      format!("$: {key} {wall} is ambiguous in {zone} ({before} and {after}); pass an explicit offset (Z or ±HH:MM)")
    }
  }
}

/// `Ok(None)` leaves an offset instant unchanged. `Ok(Some)` is the instant to store.
pub(crate) fn normalize_event_date(
  key: &str,
  text: &str,
  all_day: bool,
  zone: Option<&str>,
) -> Result<Option<String>, String> {
  match classify_event_date(text) {
    Ok(EventDateInput::Offset) => Ok(None),
    Ok(EventDateInput::DateOnly(_)) if all_day => all_day_instant(text, zone)
      .map(Some)
      .map_err(|error| explain(key, &error)),
    Ok(EventDateInput::DateOnly(_)) => Err(format!(
      "$: {key} is a calendar date. Set is_all_day true to keep that date, or pass a time with a numeric offset (Z or ±HH:MM) or time_zone. The server's time zone is not used"
    )),
    Ok(EventDateInput::Wall(_)) => {
      let Some(zone) = zone else {
        return Err(explain(key, &DateError::Invalid));
      };
      anchor_wall_time(text, zone)
        .map(Some)
        .map_err(|error| explain(key, &error))
    }
    Err(error) => Err(explain(key, &error)),
  }
}

pub(crate) fn classify_event_date(text: &str) -> Result<EventDateInput, DateError> {
  if let Some(date) = calendar_prefix(text) {
    let date = date.map_err(|()| DateError::ImpossibleDate)?;
    if text.len() == 10 {
      return Ok(EventDateInput::DateOnly(date));
    }
  }
  if parse_rfc3339(text).is_some() {
    return Ok(EventDateInput::Offset);
  }
  if let Some(wall) = parse_wall(text) {
    return Ok(EventDateInput::Wall(wall));
  }
  if calendar_prefix(text).is_some_and(|date| date.is_err()) {
    return Err(DateError::ImpossibleDate);
  }
  Err(DateError::Invalid)
}

pub(crate) fn anchor_wall_time(text: &str, zone: &str) -> Result<String, DateError> {
  let EventDateInput::Wall(wall) = classify_event_date(text)? else {
    return Err(DateError::Invalid);
  };
  let tz = named_zone(zone)?;
  let timestamp = disambiguate(wall, &tz, text, zone)?;
  Ok(format_zoned(timestamp, &tz))
}

/// Local midnight of a calendar date, as a UTC RFC 3339 instant.
/// `zone` is the event zone; otherwise the server Mac's zone, which is also the zone used on read.
pub(crate) fn all_day_instant(text: &str, zone: Option<&str>) -> Result<String, DateError> {
  let EventDateInput::DateOnly(date) = classify_event_date(text)? else {
    return Err(DateError::Invalid);
  };
  let time = Time::new(0, 0, 0, 0).map_err(|_| DateError::Invalid)?;
  let wall = DateTime::from_parts(date, time);
  let (tz, label) = match zone {
    Some(name) => (named_zone(name)?, name.to_string()),
    None => {
      let tz = TimeZone::system();
      let label = tz.iana_name().unwrap_or("UTC").to_string();
      (tz, label)
    }
  };
  let timestamp = disambiguate(wall, &tz, text, &label)?;
  Ok(timestamp.to_string())
}

pub(crate) fn parse_rfc3339(text: &str) -> Option<Timestamp> {
  let (date_text, time_text) = split_t(text)?;
  let date = parse_ymd(date_text)?;
  let (clock, offset_seconds) = split_offset(time_text)?;
  let (hour, minute, second, nanos) = parse_clock(clock, true)?;
  timestamp_from_parts(date, hour, minute, second, nanos, offset_seconds)
}

pub(crate) fn rfc3339_unix_seconds(text: &str) -> Option<f64> {
  let timestamp = parse_rfc3339(text)?;
  Some(timestamp.as_nanosecond() as f64 / 1_000_000_000.0)
}

pub(crate) fn parse_iso_unix(text: &str) -> Option<i64> {
  parse_rfc3339(text).map(|timestamp| timestamp.as_second())
}

pub(crate) fn format_unix_utc(unix: i64) -> String {
  Timestamp::from_second(unix)
    .map(|timestamp| timestamp.to_string())
    .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}

/// Timed values become local wall time with a numeric offset. All-day values become `YYYY-MM-DD`
/// in `zone`, or the server Mac's zone when the event has none.
pub(crate) fn format_event_time(raw: &str, zone: Option<&str>, all_day: bool) -> Option<String> {
  let timestamp = parse_rfc3339(raw)?;
  let tz = match zone {
    Some(name) => named_zone(name).ok()?,
    None => TimeZone::system(),
  };
  if all_day {
    Some(format_date(timestamp.to_zoned(tz).date()))
  } else {
    Some(format_zoned(timestamp, &tz))
  }
}

/// The exclusive end date of an all-day event. EventKit ends an all-day event at 23:59:59 on its
/// last day, so any end that is not exactly local midnight belongs to the following date.
pub(crate) fn format_all_day_end(raw: &str, zone: Option<&str>) -> Option<String> {
  let timestamp = parse_rfc3339(raw)?;
  let tz = match zone {
    Some(name) => named_zone(name).ok()?,
    None => TimeZone::system(),
  };
  let zoned = timestamp.to_zoned(tz);
  let date = if zoned.time() == Time::midnight() {
    zoned.date()
  } else {
    zoned.date().tomorrow().ok()?
  };
  Some(format_date(date))
}

pub(crate) fn calendar_date(year: i64, month: i64, day: i64) -> Option<String> {
  let date = Date::new(
    i16::try_from(year).ok()?,
    i8::try_from(month).ok()?,
    i8::try_from(day).ok()?,
  )
  .ok()?;
  Some(format_date(date))
}

/// Offset suffix for a unique civil time. Gaps and folds return nothing rather than a guessed offset.
pub(crate) fn zone_offset_suffix(
  zone: &str,
  year: i64,
  month: i64,
  day: i64,
  hour: i64,
  minute: i64,
  second: i64,
) -> Option<String> {
  let date = Date::new(
    i16::try_from(year).ok()?,
    i8::try_from(month).ok()?,
    i8::try_from(day).ok()?,
  )
  .ok()?;
  let time = Time::new(
    i8::try_from(hour).ok()?,
    i8::try_from(minute).ok()?,
    i8::try_from(second).ok()?,
    0,
  )
  .ok()?;
  let wall = DateTime::from_parts(date, time);
  let tz = named_zone(zone).ok()?;
  match tz.to_ambiguous_timestamp(wall).offset() {
    AmbiguousOffset::Unambiguous { offset } => Some(format_offset(offset)),
    AmbiguousOffset::Gap { .. } | AmbiguousOffset::Fold { .. } => None,
  }
}

/// Gregorian date of a Unix day count, for timestamps `jiff`'s `Timestamp` range does not cover.
pub(crate) fn date_from_unix_days(days: i64) -> Option<Date> {
  let span = Span::new().try_days(days).ok()?;
  Date::new(1970, 1, 1).ok()?.checked_add(span).ok()
}

fn timestamp_from_parts(
  date: Date,
  hour: i8,
  minute: i8,
  second: i8,
  nanos: i32,
  offset_seconds: i32,
) -> Option<Timestamp> {
  let time = Time::new(hour, minute, second, nanos).ok()?;
  let wall = DateTime::from_parts(date, time);
  let offset = Offset::from_seconds(offset_seconds).ok()?;
  offset.to_timestamp(wall).ok()
}

fn disambiguate(wall: DateTime, tz: &TimeZone, text: &str, zone: &str) -> Result<Timestamp, DateError> {
  match tz.to_ambiguous_timestamp(wall).offset() {
    AmbiguousOffset::Unambiguous { offset } => offset.to_timestamp(wall).map_err(|_| DateError::Invalid),
    AmbiguousOffset::Gap { before, after } => Err(DateError::Gap {
      wall: text.to_string(),
      zone: zone.to_string(),
      before: format_offset(before),
      after: format_offset(after),
    }),
    AmbiguousOffset::Fold { before, after } => Err(DateError::Fold {
      wall: text.to_string(),
      zone: zone.to_string(),
      before: format_offset(before),
      after: format_offset(after),
    }),
  }
}

fn named_zone(name: &str) -> Result<TimeZone, DateError> {
  let name = match name {
    "GMT" | "Etc/UTC" | "Etc/GMT" | "Etc/GMT0" => "UTC",
    other => other,
  };
  TimeZone::get(name).map_err(|_| DateError::UnknownZone)
}

fn format_zoned(timestamp: Timestamp, tz: &TimeZone) -> String {
  let zoned = timestamp.to_zoned(tz.clone());
  let wall = zoned.datetime();
  format!(
    "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}{}",
    wall.year(),
    wall.month(),
    wall.day(),
    wall.hour(),
    wall.minute(),
    wall.second(),
    format_offset(zoned.offset())
  )
}

fn format_date(date: Date) -> String {
  format!("{:04}-{:02}-{:02}", date.year(), date.month(), date.day())
}

fn format_offset(offset: Offset) -> String {
  let seconds = offset.seconds();
  if seconds == 0 {
    return "Z".to_string();
  }
  let sign = if seconds < 0 { '-' } else { '+' };
  let abs = seconds.unsigned_abs();
  let hours = abs / 3_600;
  let minutes = (abs % 3_600) / 60;
  let secs = abs % 60;
  if secs == 0 {
    format!("{sign}{hours:02}:{minutes:02}")
  } else {
    format!("{sign}{hours:02}:{minutes:02}:{secs:02}")
  }
}

fn parse_wall(text: &str) -> Option<DateTime> {
  let (date_text, time_text) = split_t(text)?;
  if time_has_offset(time_text) {
    return None;
  }
  let date = parse_ymd(date_text)?;
  let (hour, minute, second, nanos) = parse_clock(time_text, false)?;
  let time = Time::new(hour, minute, second, nanos).ok()?;
  Some(DateTime::from_parts(date, time))
}

fn calendar_prefix(text: &str) -> Option<Result<Date, ()>> {
  let bytes = text.as_bytes();
  if !ymd_shape(bytes) {
    return None;
  }
  Some(parse_ymd_bytes(&bytes[..10]).ok_or(()))
}

fn parse_ymd(text: &str) -> Option<Date> {
  let bytes = text.as_bytes();
  if bytes.len() != 10 || !ymd_shape(bytes) {
    return None;
  }
  parse_ymd_bytes(bytes)
}

fn parse_ymd_bytes(bytes: &[u8]) -> Option<Date> {
  let year = ascii_int(&bytes[..4])?;
  let month = ascii_int(&bytes[5..7])?;
  let day = ascii_int(&bytes[8..10])?;
  Date::new(
    i16::try_from(year).ok()?,
    i8::try_from(month).ok()?,
    i8::try_from(day).ok()?,
  )
  .ok()
}

fn ymd_shape(bytes: &[u8]) -> bool {
  bytes.len() >= 10
    && bytes[4] == b'-'
    && bytes[7] == b'-'
    && bytes[..4].iter().all(u8::is_ascii_digit)
    && bytes[5..7].iter().all(u8::is_ascii_digit)
    && bytes[8..10].iter().all(u8::is_ascii_digit)
}

fn split_t(text: &str) -> Option<(&str, &str)> {
  text.split_once('T').or_else(|| text.split_once('t'))
}

fn time_has_offset(time: &str) -> bool {
  let bytes = time.as_bytes();
  bytes.last().is_some_and(|byte| *byte == b'Z' || *byte == b'z')
    || bytes.iter().any(|byte| *byte == b'+' || *byte == b'-')
}

/// RFC 3339 offset: `Z`/`z` or `±HH:MM`. Anything else, including non-ASCII, is rejected.
fn split_offset(time: &str) -> Option<(&str, i32)> {
  if !time.is_ascii() {
    return None;
  }
  let bytes = time.as_bytes();
  if matches!(bytes.last(), Some(b'Z' | b'z')) {
    return Some((&time[..time.len() - 1], 0));
  }
  let index = bytes.iter().rposition(|byte| *byte == b'+' || *byte == b'-')?;
  if index == 0 {
    return None;
  }
  let body = &time[index..];
  let body_bytes = body.as_bytes();
  if body_bytes.len() != 6 || body_bytes[3] != b':' {
    return None;
  }
  let sign = if body_bytes[0] == b'-' { -1 } else { 1 };
  let hours = ascii_int(&body_bytes[1..3])?;
  let minutes = ascii_int(&body_bytes[4..6])?;
  if hours > 23 || minutes > 59 {
    return None;
  }
  Some((&time[..index], sign * (hours * 3_600 + minutes * 60)))
}

fn parse_clock(clock: &str, require_seconds: bool) -> Option<(i8, i8, i8, i32)> {
  if !clock.is_ascii() {
    return None;
  }
  let bytes = clock.as_bytes();
  if bytes.len() < 5 || bytes[2] != b':' {
    return None;
  }
  let hour = ascii_int(&bytes[..2])?;
  let minute = ascii_int(&bytes[3..5])?;
  if hour > 23 || minute > 59 {
    return None;
  }
  if bytes.len() == 5 {
    if require_seconds {
      return None;
    }
    return Some((hour as i8, minute as i8, 0, 0));
  }
  if bytes.len() < 8 || bytes[5] != b':' {
    return None;
  }
  let second = ascii_int(&bytes[6..8])?;
  if second > 59 {
    return None;
  }
  let nanos = if bytes.len() == 8 {
    0
  } else if bytes.get(8) == Some(&b'.') {
    parse_fraction(&bytes[9..])?
  } else {
    return None;
  };
  Some((hour as i8, minute as i8, second as i8, nanos))
}

fn parse_fraction(digits: &[u8]) -> Option<i32> {
  if digits.is_empty() || !digits.iter().all(u8::is_ascii_digit) {
    return None;
  }
  let mut nanos = 0i32;
  for (index, byte) in digits.iter().take(9).enumerate() {
    let place = 10i32.pow(u32::try_from(8 - index).ok()?);
    nanos += i32::from(byte - b'0') * place;
  }
  Some(nanos)
}

fn ascii_int(bytes: &[u8]) -> Option<i32> {
  if bytes.is_empty() || !bytes.iter().all(u8::is_ascii_digit) {
    return None;
  }
  std::str::from_utf8(bytes).ok()?.parse().ok()
}

#[cfg(test)]
mod tests {
  use super::{
    anchor_wall_time, classify_event_date, explain, format_all_day_end, format_event_time, parse_rfc3339,
    rfc3339_unix_seconds,
  };

  #[test]
  fn malformed_and_impossible_dates_are_rejected() {
    let rejected = [
      "2026-10-19T09:00:00+a€",
      "2026-10-19T09:00:00+1€",
      "2026-02-31",
      "2026-02-31T00:00:00",
      "2026-02-31T00:00:00Z",
      "2025-02-29",
      "2026-04-31",
      "2026-13-01",
      "2024-99-99T12:00:00Z",
      "2024-1-5T1:2:3Z",
      "not-a-date",
    ];
    for text in rejected {
      assert!(classify_event_date(text).is_err(), "{text}");
      assert!(parse_rfc3339(text).is_none(), "{text}");
    }
    assert!(classify_event_date("2024-02-29").is_ok());
    assert!(parse_rfc3339("2024-02-29T00:00:00Z").is_some());
    assert!(classify_event_date("2026-02-31").is_err());
    assert_eq!(rfc3339_unix_seconds("1970-01-01T00:00:00Z"), Some(0.0));
    assert_eq!(rfc3339_unix_seconds("1970-01-01T00:00:00.500Z"), Some(0.5));
    assert_eq!(rfc3339_unix_seconds("1970-01-01T01:00:00+01:00"), Some(0.0));
    assert_eq!(rfc3339_unix_seconds("2001-01-01T00:01:40Z"), Some(978_307_300.0));
  }

  #[test]
  fn new_york_gaps_folds_and_a_date_past_the_last_transition() {
    for wall in ["2026-03-08T02:30:00", "2027-03-14T02:30:00"] {
      let text = explain(
        "start_date",
        &anchor_wall_time(wall, "America/New_York").expect_err(wall),
      );
      assert!(
        text.contains(wall) && text.contains("America/New_York") && text.contains("gap"),
        "{text}"
      );
    }
    for wall in ["2026-11-01T01:30:00", "2027-11-07T01:30:00"] {
      let text = explain(
        "start_date",
        &anchor_wall_time(wall, "America/New_York").expect_err(wall),
      );
      assert!(
        text.contains(wall) && text.contains("explicit offset") && text.contains("America/New_York"),
        "{text}"
      );
    }
    // The installed TZif lists explicit transitions through 2037-11-01; July 2100 follows the POSIX footer.
    assert_eq!(
      anchor_wall_time("2100-07-15T12:00:00", "America/New_York").expect("summer"),
      "2100-07-15T12:00:00-04:00"
    );
    assert_eq!(
      anchor_wall_time("2100-01-15T12:00:00", "America/New_York").expect("winter"),
      "2100-01-15T12:00:00-05:00"
    );
    assert_eq!(
      anchor_wall_time("2026-10-19T09:00:00", "America/New_York").expect("edt"),
      "2026-10-19T09:00:00-04:00"
    );
  }

  #[test]
  fn all_day_serialized_instants_are_calendar_dates() {
    let cases = [
      (
        "2026-10-19T04:00:00Z",
        "2026-10-20T04:00:00Z",
        "America/New_York",
        "2026-10-19",
        "2026-10-20",
      ),
      (
        "2026-10-19T07:00:00Z",
        "2026-10-20T07:00:00Z",
        "America/Los_Angeles",
        "2026-10-19",
        "2026-10-20",
      ),
      (
        "2026-10-18T15:00:00Z",
        "2026-10-19T15:00:00Z",
        "Asia/Tokyo",
        "2026-10-19",
        "2026-10-20",
      ),
    ];
    for (start, end, zone, start_day, end_day) in cases {
      assert_eq!(
        format_event_time(start, Some(zone), true).as_deref(),
        Some(start_day),
        "{zone}"
      );
      assert_eq!(format_all_day_end(end, Some(zone)).as_deref(), Some(end_day), "{zone}");
    }
  }

  #[test]
  fn all_day_end_at_the_last_second_is_the_next_date() {
    let cases = [
      ("2026-10-24T03:59:59Z", "America/New_York", "2026-10-24"),
      ("2026-10-23T14:59:59Z", "Asia/Tokyo", "2026-10-24"),
      ("2026-10-24T06:59:59Z", "America/Los_Angeles", "2026-10-24"),
    ];
    for (end, zone, end_day) in cases {
      assert_eq!(format_all_day_end(end, Some(zone)).as_deref(), Some(end_day), "{zone}");
    }
  }
}
