#!/usr/bin/env bash
# Rasterize icon/vectors/mark.svg to a macOS menu-bar template imageset.
# Writes ABridge/Assets.xcassets/MenuBarMark.imageset (18/36/54 px, alpha-only).
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
icons_dir=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$icons_dir/.." && pwd)
src="$icons_dir/vectors/mark.svg"
dest="$repo_root/ABridge/Assets.xcassets/MenuBarMark.imageset"
point_size=18

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "gen-menubar-icons: missing $1 (brew install imagemagick)" >&2
    exit 1
  fi
}
need magick

if [[ ! -f "$src" ]]; then
  echo "gen-menubar-icons: missing $src (run icon/scripts/trace-mark.sh first)" >&2
  exit 1
fi

mkdir -p "$dest"

for scale in 1 2 3; do
  px=$((point_size * scale))
  big=$((px * 8))
  magick -background none -density 1200 "$src" \
    -resize "${big}x${big}" \
    -gravity center -background none -extent "${big}x${big}" \
    -filter Box -resize "${px}x${px}" \
    -channel RGB -evaluate set 0 +channel \
    -define png:color-type=6 \
    "$dest/MenuBarMark@${scale}x.png"
done

cat >"$dest/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "MenuBarMark@1x.png",
      "idiom" : "mac",
      "scale" : "1x"
    },
    {
      "filename" : "MenuBarMark@2x.png",
      "idiom" : "mac",
      "scale" : "2x"
    },
    {
      "filename" : "MenuBarMark@3x.png",
      "idiom" : "mac",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
JSON

echo "wrote $dest"
