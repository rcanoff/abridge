//! Fuzzy search over multi-field documents.
//!
//! Space-separated terms must all match, and a term may match any field or any line of a field
//! marked `per_line`. A fuzzy term matches inside one word — a run of letters or digits, keeping a
//! hyphen or apostrophe inside the word — so a typo or subsequence stays in that word. `^` and `$`
//! anchor the start or end of a word, including either side of a hyphen or apostrophe (`^known`
//! matches `well-known`). Matching is case-insensitive and accent-insensitive (`acao` matches
//! `ação`). `"buy milk"` is one exact phrase: spaces inside the quotes stay, and the phrase is
//! case- and accent-insensitive. A stray unmatched `"` is stripped. `'term` is an exact substring
//! of one span and does not quote spaces (`'pão de queijo'` stays three terms). `!term` excludes a
//! match, and `term | term` matches either. The score is the sum of each term's best nucleo score
//! times that field's weight.

use std::borrow::Cow;

use nucleo_matcher::pattern::{Atom, AtomKind, CaseMatching, Normalization};
use nucleo_matcher::{Config, Matcher, Utf32Str};

const EXCERPT_CHARS: usize = 120;
/// Nucleo awards 16 points per matched character before bonuses. A floor under that drops a
/// hole-ridden in-word hit while keeping a one-character typo (`chage` in `charger`).
const MIN_SCORE_PER_CHAR: u32 = 12;

pub(crate) struct Field<'a> {
  pub label: Cow<'a, str>,
  pub text: &'a str,
  pub weight: u32,
  pub per_line: bool,
}

pub(crate) struct Hit {
  pub index: usize,
  pub score: u32,
  pub matches: Vec<Match>,
}

pub(crate) struct Match {
  pub field: String,
  pub excerpt: String,
}

pub(crate) fn search(docs: &[Vec<Field<'_>>], query: &str, offset: usize, limit: usize) -> Vec<Hit> {
  if limit == 0 {
    return Vec::new();
  }
  let groups = parse_groups(query);
  if groups.is_empty() {
    return Vec::new();
  }
  let mut matcher = Matcher::new(Config::DEFAULT);
  let mut buf = Vec::new();
  let mut indices = Vec::new();
  let mut hits = Vec::new();
  for (index, doc) in docs.iter().enumerate() {
    if let Some(hit) = score_doc(index, doc, &groups, &mut matcher, &mut buf, &mut indices) {
      hits.push(hit);
    }
  }
  hits.sort_by(|left, right| right.score.cmp(&left.score).then(left.index.cmp(&right.index)));
  hits.into_iter().skip(offset).take(limit).collect()
}

fn score_doc(
  index: usize,
  doc: &[Field<'_>],
  groups: &[Vec<Atom>],
  matcher: &mut Matcher,
  buf: &mut Vec<char>,
  indices: &mut Vec<u32>,
) -> Option<Hit> {
  let mut total = 0u32;
  let mut scored = Vec::new();
  for group in groups {
    let placed = match_group(doc, group, matcher, buf, indices)?;
    if let Some(placed) = placed {
      total = total.saturating_add(placed.score);
      scored.push(placed);
    }
  }
  scored.sort_by_key(|placed| std::cmp::Reverse(placed.score));
  Some(Hit {
    index,
    score: total,
    matches: scored
      .into_iter()
      .map(|placed| Match {
        field: placed.field,
        excerpt: placed.excerpt,
      })
      .collect(),
  })
}

/// `Some(None)` means the group matched only by a negative term (no excerpt). `None` means it failed.
fn match_group(
  doc: &[Field<'_>],
  group: &[Atom],
  matcher: &mut Matcher,
  buf: &mut Vec<char>,
  indices: &mut Vec<u32>,
) -> Option<Option<Placed>> {
  let mut best: Option<Placed> = None;
  let mut matched = false;
  for atom in group {
    if atom.negative {
      if !negative_hits(doc, atom, matcher, buf) {
        matched = true;
      }
      continue;
    }
    let Some(placed) = best_place(doc, atom, matcher, buf, indices) else {
      continue;
    };
    matched = true;
    if best.as_ref().is_none_or(|current| placed.score > current.score) {
      best = Some(placed);
    }
  }
  matched.then_some(best)
}

fn best_place(
  doc: &[Field<'_>],
  atom: &Atom,
  matcher: &mut Matcher,
  buf: &mut Vec<char>,
  indices: &mut Vec<u32>,
) -> Option<Placed> {
  let mut best: Option<Placed> = None;
  for field in doc {
    if field.weight == 0 {
      continue;
    }
    each_text(field, |text| {
      let Some(raw) = match_text(atom, text, matcher, buf, indices) else {
        return;
      };
      let weighted = u32::from(raw).saturating_mul(field.weight);
      if best.as_ref().is_some_and(|placed| weighted <= placed.score) {
        return;
      }
      best = Some(Placed {
        score: weighted,
        field: field.label.to_string(),
        excerpt: excerpt(text, indices),
      });
    });
  }
  best
}

fn negative_hits(doc: &[Field<'_>], atom: &Atom, matcher: &mut Matcher, buf: &mut Vec<char>) -> bool {
  let mut found = false;
  for field in doc {
    each_text(field, |text| {
      // A negative atom scores `None` when the needle is present.
      if term_present(atom, text, matcher, buf) {
        found = true;
      }
    });
  }
  found
}

fn match_text(
  atom: &Atom,
  text: &str,
  matcher: &mut Matcher,
  buf: &mut Vec<char>,
  indices: &mut Vec<u32>,
) -> Option<u16> {
  let needle_len = atom.needle_text().len();
  let mut best_score: Option<u16> = None;
  let mut best_indices = Vec::new();
  each_span(text, atom.kind, |span| {
    indices.clear();
    let Some(score) = atom.indices(Utf32Str::new(span.text, buf), matcher, indices) else {
      return;
    };
    if atom.kind == AtomKind::Fuzzy && !fuzzy_keeps(score, indices, needle_len) {
      return;
    }
    if best_score.is_some_and(|current| score <= current) {
      return;
    }
    best_score = Some(score);
    best_indices.clear();
    best_indices.extend(indices.iter().map(|index| index.saturating_add(span.char_start)));
  });
  let score = best_score?;
  indices.clear();
  indices.extend_from_slice(&best_indices);
  Some(score)
}

fn term_present(atom: &Atom, text: &str, matcher: &mut Matcher, buf: &mut Vec<char>) -> bool {
  let mut found = false;
  each_span(text, atom.kind, |span| {
    if !found && atom.score(Utf32Str::new(span.text, buf), matcher).is_none() {
      found = true;
    }
  });
  found
}

fn fuzzy_keeps(score: u16, indices: &[u32], needle_len: usize) -> bool {
  let (Some(&first), Some(&last)) = (indices.first(), indices.last()) else {
    return false;
  };
  let span = (last.saturating_sub(first) + 1) as usize;
  let slack = 1 + needle_len / 8;
  if span > needle_len.saturating_add(slack) {
    return false;
  }
  u32::from(score) >= (needle_len as u32).saturating_mul(MIN_SCORE_PER_CHAR)
}

fn each_text(field: &Field<'_>, mut visit: impl FnMut(&str)) {
  if field.per_line {
    for line in field.text.split('\n') {
      let line = line.trim_end_matches('\r');
      if !line.is_empty() {
        visit(line);
      }
    }
  } else if !field.text.is_empty() {
    visit(field.text);
  }
}

struct Placed {
  score: u32,
  field: String,
  excerpt: String,
}

fn excerpt(text: &str, indices: &[u32]) -> String {
  let chars: Vec<char> = text.chars().collect();
  if chars.is_empty() {
    return String::new();
  }
  let mut matched = vec![false; chars.len()];
  for index in indices {
    if let Some(slot) = matched.get_mut(*index as usize) {
      *slot = true;
    }
  }
  let first = matched.iter().position(|flag| *flag).unwrap_or(0);
  let last = matched.iter().rposition(|flag| *flag).unwrap_or(first);
  let (start, end) = excerpt_window(chars.len(), first, last);
  let mut out = String::new();
  let mut index = start;
  while index < end {
    if matched[index] {
      out.push('«');
      while index < end && matched[index] {
        out.push(chars[index]);
        index += 1;
      }
      out.push('»');
    } else {
      out.push(chars[index]);
      index += 1;
    }
  }
  out
}

fn excerpt_window(len: usize, first: usize, last: usize) -> (usize, usize) {
  let last = last.min(len.saturating_sub(1));
  let first = first.min(last);
  let mut start = first;
  let mut end = last + 1;
  if end - start > EXCERPT_CHARS {
    end = start + EXCERPT_CHARS;
    return (start, end.min(len));
  }
  let pad = EXCERPT_CHARS - (end - start);
  start = first.saturating_sub(pad / 2);
  end = (last + 1 + (pad - pad / 2)).min(len);
  if end - start < EXCERPT_CHARS.min(len) {
    if start == 0 {
      end = (start + EXCERPT_CHARS).min(len);
    } else {
      start = end.saturating_sub(EXCERPT_CHARS);
    }
  }
  (start, end)
}

/// AND of OR-groups. `|` joins alternatives, with or without spaces around it.
/// A `"..."` segment is one phrase atom and is not split on spaces or `|`.
fn parse_groups(query: &str) -> Vec<Vec<Atom>> {
  let tokens = tokenize(query);
  let mut groups = Vec::new();
  let mut index = 0;
  while index < tokens.len() {
    if token_is_pipe(&tokens[index]) {
      index += 1;
      continue;
    }
    let mut atoms = Vec::new();
    push_token(&mut atoms, &tokens[index]);
    index += 1;
    while index < tokens.len() && token_is_pipe(&tokens[index]) {
      index += 1;
      while index < tokens.len() && token_is_pipe(&tokens[index]) {
        index += 1;
      }
      if index >= tokens.len() {
        break;
      }
      push_token(&mut atoms, &tokens[index]);
      index += 1;
    }
    if !atoms.is_empty() {
      groups.push(atoms);
    }
  }
  groups
}

fn token_is_pipe(token: &Token<'_>) -> bool {
  matches!(token, Token::Text(text) if text.as_ref() == "|")
}

fn push_token(atoms: &mut Vec<Atom>, token: &Token<'_>) {
  match token {
    Token::Phrase(phrase) => {
      let folded: String = phrase.chars().map(nucleo_matcher::chars::normalize).collect();
      let atom = Atom::new(
        &folded,
        CaseMatching::Ignore,
        Normalization::Smart,
        AtomKind::Substring,
        false,
      );
      if !atom.needle_text().is_empty() {
        atoms.push(atom);
      }
    }
    Token::Text(text) => push_alternatives(atoms, text),
  }
}

fn push_alternatives(atoms: &mut Vec<Atom>, token: &str) {
  for piece in split_alternatives(token) {
    if piece.is_empty() {
      continue;
    }
    let atom = Atom::parse(piece, CaseMatching::Ignore, Normalization::Smart);
    if !atom.needle_text().is_empty() {
      atoms.push(atom);
    }
  }
}

enum Token<'a> {
  /// Ordinary query text. `|` inside it is still an alternative split.
  Text(Cow<'a, str>),
  /// Exact phrase. Spaces stay; `|` is literal.
  Phrase(&'a str),
}

/// Splits on spaces and `|`. A closed `"..."` is one phrase. An unmatched `"` is omitted, so
/// `buy"milk` is the single term `buymilk` and `"buy milk` is the words `buy` and `milk`.
fn tokenize(query: &str) -> Vec<Token<'_>> {
  let mut tokens = Vec::new();
  let mut parts: Vec<&str> = Vec::new();
  let mut index = 0;
  while index < query.len() {
    let Some(character) = next_char(query, index) else {
      break;
    };
    if character == '\\' {
      let next = index + character.len_utf8();
      let end = next_char(query, next).map_or(next, |escaped| next + escaped.len_utf8());
      parts.push(&query[index..end]);
      index = end;
      continue;
    }
    if character == '"' {
      let interior_start = index + character.len_utf8();
      if let Some(close) = closing_quote(query, interior_start) {
        flush_text(&mut tokens, &mut parts);
        let interior = &query[interior_start..close];
        if !interior.is_empty() {
          tokens.push(Token::Phrase(interior));
        }
        index = close + character.len_utf8();
        continue;
      }
      index = interior_start;
      continue;
    }
    if character == ' ' || character == '|' {
      flush_text(&mut tokens, &mut parts);
      if character == '|' {
        tokens.push(Token::Text(Cow::Borrowed("|")));
      }
      index += character.len_utf8();
      continue;
    }
    let start = index;
    index += character.len_utf8();
    while index < query.len() {
      let Some(next) = next_char(query, index) else {
        break;
      };
      if next == '\\' || next == '"' || next == ' ' || next == '|' {
        break;
      }
      index += next.len_utf8();
    }
    parts.push(&query[start..index]);
  }
  flush_text(&mut tokens, &mut parts);
  tokens
}

fn closing_quote(query: &str, from: usize) -> Option<usize> {
  let mut escaped = false;
  let mut index = from;
  while index < query.len() {
    let character = next_char(query, index)?;
    if escaped {
      escaped = false;
      index += character.len_utf8();
      continue;
    }
    if character == '\\' {
      escaped = true;
      index += character.len_utf8();
      continue;
    }
    if character == '"' {
      return Some(index);
    }
    index += character.len_utf8();
  }
  None
}

fn flush_text<'a>(tokens: &mut Vec<Token<'a>>, parts: &mut Vec<&'a str>) {
  if parts.is_empty() {
    return;
  }
  let token = if parts.len() == 1 {
    Token::Text(Cow::Borrowed(parts[0]))
  } else {
    Token::Text(Cow::Owned(parts.concat()))
  };
  parts.clear();
  tokens.push(token);
}

fn split_alternatives(token: &str) -> Vec<&str> {
  let mut parts = Vec::new();
  let mut start = 0;
  let mut escaped = false;
  for (index, character) in token.char_indices() {
    if escaped {
      escaped = false;
      continue;
    }
    if character == '\\' {
      escaped = true;
      continue;
    }
    if character == '|' {
      parts.push(&token[start..index]);
      start = index + character.len_utf8();
    }
  }
  parts.push(&token[start..]);
  parts
}

#[derive(Clone, Copy)]
struct Word<'a> {
  text: &'a str,
  char_start: u32,
}

struct Words<'a> {
  text: &'a str,
  byte: usize,
  char_index: u32,
}

impl<'a> Words<'a> {
  fn new(text: &'a str) -> Self {
    Self {
      text,
      byte: 0,
      char_index: 0,
    }
  }
}

impl<'a> Iterator for Words<'a> {
  type Item = Word<'a>;

  fn next(&mut self) -> Option<Word<'a>> {
    let text = self.text;
    while self.byte < text.len() {
      let ch = next_char(text, self.byte)?;
      if is_word_char(ch) {
        break;
      }
      self.byte += ch.len_utf8();
      self.char_index += 1;
    }
    if self.byte >= text.len() {
      return None;
    }

    let start_byte = self.byte;
    let start_char = self.char_index;
    let ch = next_char(text, self.byte)?;
    self.byte += ch.len_utf8();
    self.char_index += 1;

    loop {
      if self.byte >= text.len() {
        break;
      }
      let ch = next_char(text, self.byte)?;
      if is_word_char(ch) {
        self.byte += ch.len_utf8();
        self.char_index += 1;
        continue;
      }
      if !is_connector(ch) {
        break;
      }
      let mut look_byte = self.byte;
      let mut look_chars = 0u32;
      let mut joined = false;
      while look_byte < text.len() {
        let Some(look) = next_char(text, look_byte) else {
          break;
        };
        if is_connector(look) {
          look_byte += look.len_utf8();
          look_chars += 1;
          continue;
        }
        joined = is_word_char(look);
        break;
      }
      if !joined {
        break;
      }
      self.byte = look_byte;
      self.char_index += look_chars;
    }

    Some(Word {
      text: &text[start_byte..self.byte],
      char_start: start_char,
    })
  }
}

fn each_span(text: &str, kind: AtomKind, mut visit: impl FnMut(Word<'_>)) {
  if kind == AtomKind::Substring {
    visit(Word { text, char_start: 0 });
    return;
  }
  for word in Words::new(text) {
    let compound = word.text.chars().any(is_connector);
    visit(word);
    if kind != AtomKind::Fuzzy && compound {
      for run in runs_of(&word) {
        visit(run);
      }
    }
  }
}

fn runs_of<'a>(word: &Word<'a>) -> Vec<Word<'a>> {
  let mut runs = Vec::new();
  let mut run_start_byte: Option<usize> = None;
  let mut run_start_char = 0u32;
  let mut run_end_byte = 0usize;
  for (char_index, (rel_byte, ch)) in word.text.char_indices().enumerate() {
    let char_index = u32::try_from(char_index).unwrap_or(u32::MAX);
    if is_word_char(ch) {
      if run_start_byte.is_none() {
        run_start_byte = Some(rel_byte);
        run_start_char = char_index;
      }
      run_end_byte = rel_byte + ch.len_utf8();
    } else if let Some(start) = run_start_byte.take() {
      runs.push(Word {
        text: &word.text[start..run_end_byte],
        char_start: word.char_start + run_start_char,
      });
    }
  }
  if let Some(start) = run_start_byte {
    runs.push(Word {
      text: &word.text[start..run_end_byte],
      char_start: word.char_start + run_start_char,
    });
  }
  runs
}

fn next_char(text: &str, byte: usize) -> Option<char> {
  text.get(byte..)?.chars().next()
}

fn is_word_char(character: char) -> bool {
  character.is_alphanumeric()
}

fn is_connector(character: char) -> bool {
  matches!(
    character,
    '-' | '\u{2010}' | '\u{2011}' | '\'' | '\u{2019}' | '\u{02BC}'
  )
}

#[cfg(test)]
mod tests {
  use super::{Field, search};

  fn field<'a>(label: &'a str, text: &'a str, weight: u32, per_line: bool) -> Field<'a> {
    Field {
      label: label.into(),
      text,
      weight,
      per_line,
    }
  }

  fn indexes(docs: &[Vec<Field<'_>>], query: &str) -> Vec<usize> {
    search(docs, query, 0, 10).iter().map(|hit| hit.index).collect()
  }

  #[test]
  fn terms_must_match_across_fields_and_lines() {
    let docs = vec![
      vec![field("title", "red", 1, false), field("body", "wagon", 1, false)],
      vec![field("title", "red", 1, false)],
      vec![field("body", "red\nwagon", 1, true)],
      vec![field("body", "red", 1, true)],
      vec![
        field("title", "Tesla", 2, false),
        field("body", "wall charger outside", 1, false),
      ],
    ];
    assert_eq!(indexes(&docs, "red wagon"), vec![0, 2]);
    assert_eq!(indexes(&docs, "tesla charger"), vec![4]);
  }

  #[test]
  fn keeps_typos_inside_one_word_and_drops_cross_word_scatter() {
    let docs = vec![
      vec![field("title", "Tesla wall charger", 1, false)],
      vec![field("title", "Team Meeting", 1, false)],
      vec![field("body", "alpha beta gamma", 1, false)],
      vec![field("ocr", "bring all the letters in this note", 1, false)],
      vec![field("ocr", "householdmanagement boilerplate", 1, false)],
      vec![field("title", "billing notes", 1, false)],
      vec![field("title", "well-known don't", 1, false)],
      vec![field("title", "a - b separated", 1, false)],
      vec![field("body", "the supercharger is here", 1, false)],
    ];
    assert_eq!(indexes(&docs, "chage"), vec![0, 8]);
    let charger = &search(&docs, "chage", 0, 1)[0];
    assert_eq!(charger.index, 0);
    assert!(charger.matches[0].excerpt.contains("«cha»r«ge»r") || charger.matches[0].excerpt.contains("charger"));

    assert_eq!(indexes(&docs, "meetng"), vec![1]);
    assert!(search(&docs, "abg", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "alpha gamma"), vec![2]);
    assert!(search(&docs, "bill", 0, 10).iter().all(|hit| hit.index != 3));
    assert!(!indexes(&docs, "bill").contains(&4));
    assert_eq!(indexes(&docs, "bill"), vec![5]);
    assert!(search(&docs, "home", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "wellknown"), vec![6]);
    assert_eq!(indexes(&docs, "dont"), vec![6]);
    assert!(search(&docs, "ab", 0, 10).is_empty());
  }

  #[test]
  fn exact_prefix_suffix_and_negation() {
    let docs = vec![
      vec![field("body", "a-b hello world", 1, false)],
      vec![field("body", "hello there", 1, false)],
      vec![field("title", "Tesla wall charger", 1, false)],
      vec![field("title", "well-known", 1, false)],
    ];
    assert!(search(&docs, "'ab", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "ab"), vec![0]);
    assert_eq!(indexes(&docs, "'Hello"), vec![0, 1]);
    assert_eq!(indexes(&docs, "'hello\\ world"), vec![0]);

    assert_eq!(indexes(&docs, "^hello"), vec![0, 1]);
    assert!(search(&docs, "^ello", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "^world"), vec![0]);
    assert_eq!(indexes(&docs, "^tes"), vec![2]);
    assert_eq!(indexes(&docs, "^Tesla"), vec![2]);
    assert_eq!(indexes(&docs, "^known"), vec![3]);
    assert_eq!(indexes(&docs, "^well"), vec![3]);

    assert_eq!(indexes(&docs, "world$"), vec![0]);
    assert_eq!(indexes(&docs, "hello$"), vec![0, 1]);
    assert!(search(&docs, "hel$", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "there$"), vec![1]);
    assert_eq!(indexes(&docs, "charger$"), vec![2]);
    assert_eq!(indexes(&docs, "well$"), vec![3]);
    assert_eq!(indexes(&docs, "known$"), vec![3]);

    assert_eq!(indexes(&docs, "hello !world"), vec![1]);
    assert_eq!(indexes(&docs, "hello !World"), vec![1]);
  }

  #[test]
  fn ignores_case_and_accents() {
    let docs = vec![
      vec![field("title", "Note", 1, false)],
      vec![field("title", "note", 1, false)],
      vec![field("title", "ação", 1, false)],
      vec![field("title", "Ação", 1, false)],
      vec![field("title", "Tesla Model", 1, false)],
    ];
    assert_eq!(indexes(&docs, "note"), vec![0, 1]);
    assert_eq!(indexes(&docs, "Note"), vec![0, 1]);
    assert_eq!(indexes(&docs, "^NOTE"), vec![0, 1]);
    let accented = indexes(&docs, "acao");
    assert_eq!(accented, vec![2, 3]);
    assert_eq!(indexes(&docs, "^tes"), vec![4]);
    assert_eq!(indexes(&docs, "^Tesla"), vec![4]);
  }

  #[test]
  fn title_weight_outranks_body_and_excerpt_marks_the_match() {
    let docs = vec![
      vec![field("body", "zebra in a long body", 1, false)],
      vec![field("title", "zebra", 10, false)],
    ];
    let hits = search(&docs, "zebra", 0, 10);
    assert_eq!(hits[0].index, 1);
    assert!(hits[0].score > hits[1].score);
    assert_eq!(hits[0].matches[0].field, "title");
    assert!(hits[0].matches[0].excerpt.contains('«'));
    assert!(hits[0].matches[0].excerpt.contains('»'));
    assert!(hits[0].matches[0].excerpt.contains("zebra"));
  }

  #[test]
  fn either_alternative_matches_and_pages_follow_score() {
    let docs = vec![
      vec![field("body", "blue", 1, false)],
      vec![field("body", "red", 5, false)],
      vec![field("body", "green", 1, false)],
    ];
    assert_eq!(indexes(&docs, "red | blue"), vec![1, 0]);
    let page = search(&docs, "red | blue", 1, 1);
    assert_eq!(page.len(), 1);
    assert_eq!(page[0].index, 0);
  }

  #[test]
  fn quoted_phrase_keeps_spaces_and_ignores_case_and_accents() {
    let docs = vec![
      vec![field("title", "Please buy milk today", 1, false)],
      vec![field("title", "BUY MILK", 1, false)],
      vec![field("title", "buy some milk", 1, false)],
      vec![field("title", "milk buy", 1, false)],
      vec![field("title", "buy", 1, false), field("body", "milk", 1, false)],
      vec![field("title", "Pão de Queijo", 1, false)],
      vec![field("title", "pao de queijo", 1, false)],
      vec![field("body", "buy\nmilk", 1, true)],
      vec![field("title", "buymilk", 1, false)],
    ];
    assert_eq!(indexes(&docs, "\"buy milk\""), vec![0, 1]);
    assert_eq!(indexes(&docs, "\"BUY MILK\""), vec![0, 1]);
    let marked = &search(&docs, "\"buy milk\"", 0, 1)[0];
    assert!(marked.matches[0].excerpt.contains("«buy milk»"));
    assert_eq!(indexes(&docs, "\"pao de queijo\""), vec![5, 6]);
    assert_eq!(indexes(&docs, "\"pão de queijo\""), vec![5, 6]);
    assert_eq!(indexes(&docs, "\"PÃO DE QUEIJO\""), vec![5, 6]);
    assert_eq!(indexes(&docs, "\"buy milk\" today"), vec![0]);
    let mut either = indexes(&docs, "\"buy milk\" | queijo");
    either.sort_unstable();
    assert_eq!(either, vec![0, 1, 5, 6]);
    assert!(search(&docs, "\"buy  milk\"", 0, 10).is_empty());
  }

  #[test]
  fn unmatched_quotes_are_stripped_and_single_quotes_do_not_group_words() {
    let docs = vec![
      vec![field("title", "Please buy milk today", 1, false)],
      vec![field("title", "buy some milk", 1, false)],
      vec![field("title", "buymilk", 1, false)],
      vec![field("title", "Pão de Queijo", 1, false)],
      vec![field("title", "pao de queijo", 1, false)],
    ];
    assert_eq!(indexes(&docs, "\"buy milk"), vec![0, 1, 2]);
    assert_eq!(indexes(&docs, "buy milk\""), vec![0, 1, 2]);
    assert_eq!(indexes(&docs, "buy\"milk"), vec![2]);
    assert!(search(&docs, "'pão de queijo'", 0, 10).is_empty());
    assert_eq!(indexes(&docs, "'pão"), vec![3]);
    assert_eq!(indexes(&docs, "\"\""), Vec::<usize>::new());
  }
}
