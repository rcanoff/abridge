#!/usr/bin/env bash
# Prints the rcanoff/homebrew-tap cask for a released ABridge DMG.
#
# Usage: scripts/homebrew-cask.sh <version> <dmg-path>
set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! -f "$2" ]]; then
    sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 64
fi

version="$1"
sha256="$(shasum -a 256 "$2" | awk '{print $1}')"

cat <<EOF
cask "abridge" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/rcanoff/abridge/releases/download/v#{version}/ABridge-#{version}.dmg"
  name "ABridge"
  desc "Local MCP server for Apple frameworks"
  homepage "https://github.com/rcanoff/abridge"

  livecheck do
    url "https://github.com/rcanoff/abridge/releases/latest/download/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "ABridge.app"

  zap trash: [
    "~/Library/Application Support/ABridge",
    "~/Library/Caches/io.github.rcanoff.ABridge",
    "~/Library/HTTPStorages/io.github.rcanoff.ABridge",
    "~/Library/Preferences/io.github.rcanoff.ABridge.plist",
  ]
end
EOF
