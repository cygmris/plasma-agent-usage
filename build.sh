#!/bin/bash
# Build a clean .plasmoid package containing ONLY metadata.json + contents/.
# Excludes tests/, .spec-workflow/, docs/, package.json, *.md, build artifacts.
set -e
cd "$(dirname "$0")"
PKG="plasma-agent-usage.plasmoid"
rm -f "$PKG"

if ! command -v zip >/dev/null; then
    echo "ERROR: 'zip' not found. Install it (e.g. 'sudo pacman -S zip')." >&2
    exit 1
fi

zip -rq "$PKG" metadata.json contents \
    -x '*/__pycache__/*' -x '*.pyc' -x '*/.git/*'

echo "Built $PKG"
echo "--- sanity check: must NOT contain excluded files ---"
if unzip -l "$PKG" | grep -qE 'tests/|\.spec-workflow/|/docs/|package\.json|\.mjs'; then
    echo "ERROR: package contains files that should be excluded:" >&2
    unzip -l "$PKG" | grep -E 'tests/|\.spec-workflow/|/docs/|package\.json|\.mjs' >&2
    exit 1
fi
echo "OK: clean package ($(unzip -l "$PKG" | tail -1 | awk '{print $2}') entries)"
echo ""
echo "Install with:  kpackagetool6 -t Plasma/Applet -i $PKG"
echo "Or run:        ./install.sh"
