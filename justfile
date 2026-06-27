# Apple Bridge — task runner (see docs/conventions.md)

test-swift:
    TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
        -only-testing:AppleBridgeTests -destination 'platform=macOS' -quiet

# Rust recipes — require rust/Cargo.toml (lands with PR 2+)
test-rust:
    cd rust && TZ=UTC cargo test

lint-rust:
    cd rust && cargo clippy -- -D warnings

build-rust:
    cd rust && ./build-macos.sh

test-all:
    just test-swift
    @if [ -f rust/Cargo.toml ]; then just test-rust; fi

clean-rust:
    cd rust && cargo clean
    rm -rf AppleBridgeCore

rebuild: clean-rust build-rust