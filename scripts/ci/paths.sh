#!/usr/bin/env bash
# Classify changed files between two refs.
# Usage: scripts/ci/paths.sh <base_ref> <head_ref>
# Exports: PATHS_RUST_CHANGED=0|1  PATHS_SWIFT_CHANGED=0|1

set -euo pipefail

BASE_REF="${1:?base ref required}"
HEAD_REF="${2:?head ref required}"

PATHS_RUST_CHANGED=0
PATHS_SWIFT_CHANGED=0

changed_files="$(git diff --name-only "${BASE_REF}"..."${HEAD_REF}" 2>/dev/null || git diff --name-only "${BASE_REF}" "${HEAD_REF}")"

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    rust/*)
      PATHS_RUST_CHANGED=1
      PATHS_SWIFT_CHANGED=1
      ;;
    AppleBridgeCore/*)
      PATHS_RUST_CHANGED=1
      PATHS_SWIFT_CHANGED=1
      ;;
    AppleBridge/*|AppleBridgeTests/*|project.yml|AppleBridge.xcodeproj/*)
      PATHS_SWIFT_CHANGED=1
      ;;
    justfile|scripts/ci/*)
      PATHS_RUST_CHANGED=1
      PATHS_SWIFT_CHANGED=1
      ;;
    .swiftformat|.swiftlint.yml)
      PATHS_SWIFT_CHANGED=1
      ;;
    .github/workflows/ci-macos.yml)
      PATHS_SWIFT_CHANGED=1
      ;;
    .github/workflows/ci-rust.yml)
      PATHS_RUST_CHANGED=1
      ;;
  esac
done <<< "$changed_files"

export PATHS_RUST_CHANGED PATHS_SWIFT_CHANGED