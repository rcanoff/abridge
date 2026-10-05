#!/usr/bin/env bash
# Prints the rcanoff/homebrew-tap cask for a released Apple Bridge DMG.
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
cask "apple-bridge" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/rcanoff/apple-bridge/releases/download/v#{version}/AppleBridge-#{version}.dmg"
  name "Apple Bridge"
  desc "Local MCP server for Apple frameworks"
  homepage "https://github.com/rcanoff/apple-bridge"

  livecheck do
    url "https://github.com/rcanoff/apple-bridge/releases/latest/download/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "AppleBridge.app"

  zap trash: [
    "~/Library/Application Support/AppleBridge",
    "~/Library/Caches/com.applebridge.AppleBridge",
    "~/Library/HTTPStorages/com.applebridge.AppleBridge",
    "~/Library/Preferences/com.applebridge.AppleBridge.plist",
  ]
end
EOF
