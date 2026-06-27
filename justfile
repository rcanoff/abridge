# Apple Bridge — task runner (see docs/conventions.md)

review *FLAGS='':
    @local/review/bin/review.sh {{FLAGS}}

review-strict:
    @local/review/bin/review.sh --strict

test-swift:
    TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
        -only-testing:AppleBridgeTests -destination 'platform=macOS' -quiet

# Guard: rust recipes require rust/Cargo.toml (lands with PR 2+)
_rust-workspace:
    @test -f rust/Cargo.toml || (echo "error: rust/Cargo.toml not found — Rust workspace lands in PR 2+" >&2 && exit 1)

test-rust: _rust-workspace
    cd rust && TZ=UTC cargo test

fmt-rust: _rust-workspace
    cd rust && cargo fmt --all

fmt-check-rust: _rust-workspace
    cd rust && cargo fmt --all -- --check

lint-rust: _rust-workspace
    just fmt-check-rust
    cd rust && cargo clippy -- -D warnings

build-rust: _rust-workspace
    cd rust && ./build-macos.sh

test-all:
    just test-swift
    @if [ -f rust/Cargo.toml ]; then just test-rust; fi

clean-rust: _rust-workspace
    cd rust && cargo clean
    rm -rf AppleBridgeCore

rebuild: clean-rust build-rust