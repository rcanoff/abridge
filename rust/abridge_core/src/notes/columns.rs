//! Core Data column names and JSON key conversion.

/// `Z` + uppercase attribute name, plus an optional numeric suffix (`ZTITLE1`).
pub(crate) fn is_attribute_column(column: &str, attribute: &str) -> bool {
  let mut prefix = String::from("Z");
  prefix.push_str(&attribute.to_ascii_uppercase());
  let Some(rest) = column.strip_prefix(&prefix) else {
    return false;
  };
  rest.chars().all(|character| character.is_ascii_digit())
}

/// `creationDate` → `creation_date`, `typeUTI` → `type_uti`.
pub(crate) fn snake_case(name: &str) -> String {
  let chars: Vec<char> = name.chars().collect();
  let mut out = String::new();
  for (index, character) in chars.iter().enumerate() {
    if character.is_uppercase() {
      let previous = index.checked_sub(1).map(|at| chars[at]);
      let next_lower = chars.get(index + 1).is_some_and(|next| next.is_lowercase());
      let boundary = match previous {
        Some(previous) if previous.is_lowercase() || previous.is_ascii_digit() => true,
        Some(previous) if previous.is_uppercase() && next_lower => true,
        _ => false,
      };
      if boundary {
        out.push('_');
      }
      out.extend(character.to_lowercase());
    } else {
      out.push(*character);
    }
  }
  out
}

#[cfg(test)]
mod tests {
  use super::{is_attribute_column, snake_case};

  #[test]
  fn column_suffix_does_not_match_longer_names() {
    assert!(is_attribute_column("ZTITLE", "title"));
    assert!(is_attribute_column("ZTITLE1", "title"));
    assert!(is_attribute_column("ZTITLE2", "title"));
    assert!(!is_attribute_column("ZTITLESOURCEATTACHMENT", "title"));
    assert!(is_attribute_column("ZACCOUNT", "account"));
    assert!(is_attribute_column("ZACCOUNT8", "account"));
    assert!(!is_attribute_column("ZACCOUNTTYPE", "account"));
    assert!(!is_attribute_column("ZNOTEDATA", "note"));
    assert!(is_attribute_column("ZNOTE", "note"));
    assert!(!is_attribute_column("ZFOLDERTYPE", "folder"));
    assert!(!is_attribute_column("ZMODIFICATIONDATEATIMPORT", "modificationDate"));
  }

  #[test]
  fn snake_case_splits_core_data_names() {
    assert_eq!(snake_case("creationDate"), "creation_date");
    assert_eq!(snake_case("typeUTI"), "type_uti");
    assert_eq!(snake_case("isPinned"), "is_pinned");
    assert_eq!(snake_case("remoteFileURLString"), "remote_file_url_string");
    assert_eq!(snake_case("fallbackSubtitleIOS"), "fallback_subtitle_ios");
    assert_eq!(snake_case("smartFolderQueryJSON"), "smart_folder_query_json");
    assert_eq!(snake_case("ocrSummary"), "ocr_summary");
  }
}
