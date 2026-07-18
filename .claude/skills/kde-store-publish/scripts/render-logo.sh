#!/bin/bash
# Render the widget SVG icon to a square PNG suitable for the KDE Store "Product Logo".
# KDE Store logo constraints: min 20x20, max 2000x2000, <=2MB. 256px is a good default.
#
# Usage: render-logo.sh [SIZE] [OUT_PATH]
#   SIZE      pixel size (default 256)
#   OUT_PATH  output png (default: <repo>/store-logo.png)
#
# NOTE: the browser upload_file tool only accepts paths inside a workspace root.
# If this repo is outside the session's workspace root, copy the result into the
# session scratchpad before uploading.
set -e
cd "$(dirname "$0")/../../../.."   # -> repo root (from .claude/skills/kde-store-publish/scripts)
SIZE="${1:-256}"
OUT="${2:-$PWD/store-logo.png}"
SVG="contents/icons/widget.svg"
[ -f "$SVG" ] || { echo "ERROR: $SVG not found (run from repo with contents/icons/widget.svg)" >&2; exit 1; }

if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w "$SIZE" -h "$SIZE" "$SVG" -o "$OUT"
elif command -v magick >/dev/null; then
    magick -background none "$SVG" -resize "${SIZE}x${SIZE}" "$OUT"
elif command -v inkscape >/dev/null; then
    inkscape "$SVG" -w "$SIZE" -h "$SIZE" -o "$OUT"
else
    echo "ERROR: need rsvg-convert / imagemagick / inkscape" >&2; exit 1
fi
echo "Rendered $OUT ($(identify -format '%wx%h' "$OUT" 2>/dev/null || echo "${SIZE}x${SIZE}"))"
