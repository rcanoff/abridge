#!/usr/bin/env bash
# Trace icon/previews/mark.jpg to icon/vectors/mark.svg (ImageMagick + potrace).
# Same locked settings as Zyrdon's face tracer: gray + normalize, 2x, 72% threshold.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
icons_dir=$(cd "$script_dir/.." && pwd)
src="$icons_dir/previews/mark.jpg"
dest="$icons_dir/vectors/mark.svg"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "trace-mark: missing $1 (brew install imagemagick potrace)" >&2
    exit 1
  fi
}
need magick
need potrace

if [[ ! -f "$src" ]]; then
  echo "trace-mark: missing $src" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

magick "$src" \
  -colorspace Gray \
  -normalize \
  -resize 200% \
  -threshold 72% \
  "$tmp/mark.pbm"

potrace "$tmp/mark.pbm" \
  -s \
  --tight \
  --alphamax 1.0 \
  --opttolerance 0.2 \
  --turdsize 3 \
  -o "$dest"

width=$(magick identify -format "%w" "$src")
height=$(magick identify -format "%h" "$src")
normalized=$(mktemp)
/usr/bin/sed -E \
  -e "s/width=\"[0-9.]+pt\"/width=\"${width}px\"/" \
  -e "s/height=\"[0-9.]+pt\"/height=\"${height}px\"/" \
  "$dest" >"$normalized"
mv "$normalized" "$dest"

echo "wrote $dest"
