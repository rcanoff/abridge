#!/usr/bin/env bash
# Capture stdout/stderr of `TZ=UTC just test-swift` only (tee, no append).
# Writes: ${SCRATCH}/test-swift.log (overwrite)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SCRATCH="${SCRATCH:-/var/folders/j1/79r1s5wn54gdrjpc78k08g5h0000gn/T/grok-goal-0858149818ca/implementer}"
LOG="${SCRATCH}/test-swift.log"

mkdir -p "$SCRATCH"

TZ=UTC just test-swift 2>&1 | tee "$LOG"
echo "Wrote $LOG"