#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/AppleBridgeCore"
XCFRAMEWORK_DIR="$OUTPUT_DIR/apple_bridge_core.xcframework"

cd "$SCRIPT_DIR"

ARM64_LIB="target/aarch64-apple-darwin/release/libapple_bridge_core.a"

echo "Building macOS arm64..."
cargo build --release -p apple_bridge_core --target aarch64-apple-darwin

mkdir -p "$OUTPUT_DIR/Sources"
mkdir -p "$OUTPUT_DIR/Headers"

MACOS_LIB_DIR="$OUTPUT_DIR/lib-macos-arm64"
mkdir -p "$MACOS_LIB_DIR"
cp "$ARM64_LIB" "$MACOS_LIB_DIR/libapple_bridge_core.a"

echo "Generating Swift bindings..."
cargo run --release -p apple_bridge_core --bin uniffi-bindgen generate \
  --library "$ARM64_LIB" \
  --language swift \
  --out-dir "$OUTPUT_DIR/Sources"

if [ -f "$OUTPUT_DIR/Sources/apple_bridge_coreFFI.h" ]; then
  mv "$OUTPUT_DIR/Sources/apple_bridge_coreFFI.h" "$OUTPUT_DIR/Headers/"
fi

cat > "$OUTPUT_DIR/Headers/module.modulemap" << 'EOF'
module apple_bridge_coreFFI {
    header "apple_bridge_coreFFI.h"
    export *
}
EOF

rm -rf "$XCFRAMEWORK_DIR"
xcodebuild -create-xcframework \
  -library "$MACOS_LIB_DIR/libapple_bridge_core.a" \
  -headers "$OUTPUT_DIR/Headers" \
  -output "$XCFRAMEWORK_DIR"

rm -rf "$MACOS_LIB_DIR" "$OUTPUT_DIR/Headers"

cp "$OUTPUT_DIR/Sources/apple_bridge_core.swift" \
  "$PROJECT_DIR/AppleBridge/Services/apple_bridge_core.swift"

echo "Done: $XCFRAMEWORK_DIR"