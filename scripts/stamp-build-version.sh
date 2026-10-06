#!/usr/bin/env bash
# Xcode build phase: stamps local builds with the git version so the About window and
# MCP serverInfo.version match the release they were built from.
#
#   CFBundleShortVersionString  `git describe --tags --dirty` without the leading "v"
#                               (e.g. 0.3.0 on a tag, 0.3.0-4-gabc1234-dirty after it)
#   CFBundleVersion             commit count of HEAD (same rule as scripts/release.sh)
#
# Release builds pass MARKETING_VERSION to xcodebuild; only the project.yml placeholder is replaced.
set -euo pipefail

[[ "$MARKETING_VERSION" == "0.0.0" ]] || exit 0

cd "$SRCROOT"
if ! version="$(git describe --tags --match 'v[0-9]*' --dirty 2>/dev/null)"; then
    echo "note: no release tag reachable; keeping placeholder version"
    exit 0
fi

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString ${version#v}" \
    -c "Set :CFBundleVersion $(git rev-list --count HEAD)" \
    "$plist"
