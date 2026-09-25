#!/usr/bin/env bash
# Builds the SD-card package dist/MIB-<version>.zip from a git commit (default HEAD).
# Developer material (dev/, tests/, .agent/, .github/) is left out via "export-ignore"
# in .gitattributes. Users extract this zip to the root of a FAT32 SD card.
#
# Usage: dev/tools/package.sh [commit]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

REV="${1:-HEAD}"
VERSION="$(git show "$REV:VERSION" | awk '{print $1; exit}')"
OUT="dist/MIB-$VERSION.zip"

mkdir -p dist
git archive --format=zip --worktree-attributes -o "$OUT" "$REV"

names="$(python3 -c 'import sys, zipfile; print("\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))' "$OUT")"

leaked="$(grep -E '^(dev|tests|\.agent|\.github)/' <<< "$names" || true)"
if [ -n "$leaked" ]; then
	echo "error: developer files in package:" >&2
	echo "$leaked" >&2
	exit 1
fi

for required in start VERSION metainfo2.txt Launcher/final/finalScript.sh esd/Launcher-sda0.esd apps/flash; do
	if ! grep -qxF "$required" <<< "$names"; then
		echo "error: $required missing from package" >&2
		exit 1
	fi
done

echo "$OUT ($(grep -vc '/$' <<< "$names") files)"
