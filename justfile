# Apple Bridge — task runner (see docs/conventions.md)

review *FLAGS='':
    @local/review/bin/review.sh {{FLAGS}}

review-strict:
    @local/review/bin/review.sh --strict

verify-issue-120:
    #!/usr/bin/env bash
    set -euo pipefail
    chmod +x scripts/verify-issue-120.sh
    scripts/verify-issue-120.sh

verify-epic-90:
    #!/usr/bin/env bash
    set -euo pipefail
    chmod +x scripts/verify-epic-90-orchestration-gates.sh
    scripts/verify-epic-90-orchestration-gates.sh

verify-epic-90-phase4-order:
    #!/usr/bin/env bash
    set -euo pipefail
    chmod +x scripts/verify-epic-90-phase4-order.sh
    scripts/verify-epic-90-phase4-order.sh

test-swift:
    #!/usr/bin/env bash
    set -euo pipefail
    # arm64-only (see main); build + test-without-building avoids destination ambiguity and pipe hangs.
    TZ=UTC xcodebuild build-for-testing -project AppleBridge.xcodeproj -scheme AppleBridge \
        -destination 'platform=macOS,arch=arm64' -quiet
    TZ=UTC xcodebuild test-without-building -project AppleBridge.xcodeproj -scheme AppleBridge \
        -only-testing:AppleBridgeTests -destination 'platform=macOS,arch=arm64' \
        -parallel-testing-enabled NO -quiet

test-swift-verbose:
    #!/usr/bin/env bash
    set -euo pipefail
    # arm64-only (see main); build + test-without-building avoids destination ambiguity and pipe hangs.
    TZ=UTC xcodebuild build-for-testing -project AppleBridge.xcodeproj -scheme AppleBridge \
        -destination 'platform=macOS,arch=arm64'
    TZ=UTC xcodebuild test-without-building -project AppleBridge.xcodeproj -scheme AppleBridge \
        -only-testing:AppleBridgeTests -destination 'platform=macOS,arch=arm64' \
        -parallel-testing-enabled NO

# Guard: rust recipes require rust/Cargo.toml (lands with PR 2+)
_rust-workspace:
    @test -f rust/Cargo.toml || (echo "error: rust/Cargo.toml not found — Rust workspace lands in PR 2+" >&2 && exit 1)

test-rust: _rust-workspace
    cd rust && TZ=UTC cargo test --features test-sync

fmt-rust: _rust-workspace
    cd rust && cargo fmt --all

fmt-check-rust: _rust-workspace
    cd rust && cargo fmt --all --check

lint-rust: _rust-workspace
    just fmt-check-rust
    cd rust && cargo clippy --features test-sync -- -D warnings

ci-rust: _rust-workspace
    just lint-rust
    just test-rust

_swift-sources := "AppleBridge AppleBridgeTests"
_swift-exclude := "--exclude AppleBridge/Services/apple_bridge_core.swift --exclude AppleBridgeCore"

fmt-swift:
    swiftformat {{_swift-sources}} {{_swift-exclude}}

fmt-check-swift:
    swiftformat {{_swift-sources}} {{_swift-exclude}} --lint

lint-swift:
    swiftlint lint --strict --quiet

# macOS CI steps (no host guard — used by GitHub Actions macos runner)
ci-macos-steps: _rust-workspace
    just fmt-check-swift
    just lint-swift
    just build-rust
    just test-swift

# Local entry point; skips gracefully off-macOS
ci-macos:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! uname | grep -qi darwin; then
      echo "skipped: ci-macos requires macOS" >&2
      exit 0
    fi
    just ci-macos-steps

ci:
    just ci-rust
    @uname | grep -qi darwin && just ci-macos-steps || echo "skipped: ci-macos (not macOS)"

# Full local CI — run before pushing to avoid failed macOS runner minutes
preflight:
    just ci

build-rust: _rust-workspace
    cd rust && ./build-macos.sh

test-all:
    just test-swift
    @if [ -f rust/Cargo.toml ]; then just test-rust; fi

test-all-verbose:
    just test-swift-verbose
    @if [ -f rust/Cargo.toml ]; then just test-rust; fi

clean-rust: _rust-workspace
    cd rust && cargo clean
    rm -rf AppleBridgeCore

rebuild: clean-rust build-rust

# Orchestration gate checks for pr3b–pr3k reminder features (docs + PR history)
verify-orchestration:
    @scripts/verify-orchestration-gates.sh
