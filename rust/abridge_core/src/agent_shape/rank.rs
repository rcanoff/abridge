//! Borrowed fields for `crate::fuzzy`, built from owned strings that outlive the search.

use std::borrow::Cow;

use serde_json::Value;

use crate::fuzzy::{self, Field};

pub(crate) struct OwnedField {
  pub label: String,
  pub text: String,
  pub weight: u32,
  pub per_line: bool,
}

pub(crate) fn rank(
  items: &[Value],
  query: &str,
  fields: impl Fn(&Value) -> Vec<OwnedField>,
  offset: usize,
  limit: usize,
) -> Vec<(usize, u32, Vec<fuzzy::Match>)> {
  let owned: Vec<Vec<OwnedField>> = items.iter().map(fields).collect();
  let docs: Vec<Vec<Field<'_>>> = owned
    .iter()
    .map(|doc| {
      doc
        .iter()
        .filter(|field| !field.text.is_empty())
        .map(|field| Field {
          label: Cow::Borrowed(field.label.as_str()),
          text: field.text.as_str(),
          weight: field.weight,
          per_line: field.per_line,
        })
        .collect()
    })
    .collect();
  fuzzy::search(&docs, query, offset, limit)
    .into_iter()
    .map(|hit| (hit.index, hit.score, hit.matches))
    .collect()
}
