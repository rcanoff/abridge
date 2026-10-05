#!/usr/bin/env bash
# Builds a Developer ID signed, notarized ABridge DMG and its Sparkle appcast.
#
# Usage: scripts/release.sh <version> [--skip-notarization]
#
#   <version>              Marketing version (CFBundleShortVersionString), e.g. 1.2.0
#   --skip-notarization    Sign and package without notarizing; the DMG is for local checks only.
#
# Environment:
#   APPLE_SIGNING_IDENTITY   Certificate name, e.g. "Developer ID Application: Name (TEAMID)" (required)
#   NOTARY_KEYCHAIN_PROFILE  notarytool keychain profile (required unless --skip-notarization)
#   NOTARY_KEYCHAIN          Keychain holding that profile (optional; default search list)
#   SPARKLE_ED_KEY_FILE      Private EdDSA key file (optional; default: keychain account "abridge")
#   BUILD_NUMBER             CFBundleVersion (optional; default: commit count of HEAD)
#
# Output: build/release/ABridge-<version>.dmg and build/release/appcast.xml
set -euo pipefail

readonly REPO_URL="https://github.com/rcanoff/abridge"
readonly SPARKLE_KEY_ACCOUNT="abridge"

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 64
}

version=""
notarize=true
for arg in "$@"; do
    case "$arg" in
    --skip-notarization) notarize=false ;;
    -*) usage ;;
    *)
        [[ -z "$version" ]] || usage
        version="$arg"
        ;;
    esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
: "${APPLE_SIGNING_IDENTITY:?APPLE_SIGNING_IDENTITY is required}"
identity_pattern='^Developer ID Application: .+ \(([A-Z0-9]{10})\)$'
if [[ ! "$APPLE_SIGNING_IDENTITY" =~ $identity_pattern ]]; then
    echo "error: APPLE_SIGNING_IDENTITY must be a \"Developer ID Application: Name (TEAMID)\" certificate name" >&2
    exit 64
fi
team_id="${BASH_REMATCH[1]}"
if $notarize; then
    : "${NOTARY_KEYCHAIN_PROFILE:?NOTARY_KEYCHAIN_PROFILE is required (or pass --skip-notarization)}"
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

build_number="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
build_dir="$root/build/release"
packages_dir="$root/build/SourcePackages"
archive="$build_dir/ABridge.xcarchive"
export_dir="$build_dir/export"
app="$export_dir/ABridge.app"
dmg="$build_dir/ABridge-$version.dmg"

identities="$(security find-identity -v -p codesigning | grep -F "\"$APPLE_SIGNING_IDENTITY\"" || true)"
if [[ "$(grep -c . <<<"$identities")" -ne 1 ]]; then
    echo "error: expected exactly one valid codesigning identity named \"$APPLE_SIGNING_IDENTITY\"" >&2
    exit 1
fi
# The SHA-1 hash pins the exact certificate for xcodebuild, export, and codesign.
signing_identity="$(awk '{print $2}' <<<"$identities")"

notarize_and_staple() {
    local submission="$1" staple_target="$2" result status submission_id
    result="$(xcrun notarytool submit "$submission" \
        --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
        ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} \
        --wait --output-format json)"
    status="$(plutil -extract status raw - <<<"$result")"
    submission_id="$(plutil -extract id raw - <<<"$result")"
    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization of $(basename "$submission") finished with status $status" >&2
        xcrun notarytool log "$submission_id" \
            --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
            ${NOTARY_KEYCHAIN:+--keychain "$NOTARY_KEYCHAIN"} >&2
        exit 1
    fi
    xcrun stapler staple "$staple_target"
}

rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "==> Building Rust core"
just build-rust

echo "==> Archiving ABridge $version ($build_number)"
xcodebuild archive \
    -project ABridge.xcodeproj \
    -scheme ABridge \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    -clonedSourcePackagesDirPath "$packages_dir" \
    -quiet \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    OTHER_CODE_SIGN_FLAGS=--timestamp

echo "==> Exporting Developer ID build"
cat >"$build_dir/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$signing_identity</string>
    <key>teamID</key>
    <string>$team_id</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$build_dir/ExportOptions.plist" \
    -quiet
codesign --verify --deep --strict --verbose=2 "$app"

if $notarize; then
    echo "==> Notarizing app"
    ditto -c -k --keepParent "$app" "$build_dir/ABridge-notarization.zip"
    notarize_and_staple "$build_dir/ABridge-notarization.zip" "$app"
fi

echo "==> Creating DMG"
staging="$build_dir/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/ABridge.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "ABridge" -srcfolder "$staging" -fs APFS -format ULFO -ov "$dmg"
codesign --sign "$signing_identity" --timestamp "$dmg"

if $notarize; then
    echo "==> Notarizing DMG"
    notarize_and_staple "$dmg" "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
    spctl --assess --type execute --verbose=2 "$app"
fi

echo "==> Generating appcast"
appcast_dir="$build_dir/appcast"
mkdir -p "$appcast_dir"
cp "$dmg" "$appcast_dir/"
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
    key_args=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
else
    key_args=(--account "$SPARKLE_KEY_ACCOUNT")
fi
"$packages_dir/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "${key_args[@]}" \
    --download-url-prefix "$REPO_URL/releases/download/v$version/" \
    --full-release-notes-url "$REPO_URL/releases/tag/v$version" \
    --link "$REPO_URL" \
    -o "$build_dir/appcast.xml" \
    "$appcast_dir"

echo "==> Done"
echo "$dmg"
echo "$build_dir/appcast.xml"
