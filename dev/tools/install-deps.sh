#!/usr/bin/env bash
# Installs the host-side developer tools for M.I.B. into dev/.tools/ (no root needed).
#
# Tools: mksh (reference shell, closest to the QNX Korn shell), shellcheck, bc, xxd.
# Tools already on PATH are reused. Missing Debian/Ubuntu packages are fetched with
# "apt-get download" and unpacked locally; shellcheck comes from its GitHub release
# and is verified against a pinned SHA-256.
#
# Usage: dev/tools/install-deps.sh          then: export PATH="$PWD/dev/.tools/bin:$PATH"
#        (dev/tools/lint.sh and the other dev scripts add dev/.tools/bin to PATH themselves)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$ROOT/dev/.tools"
BIN="$TOOLS/bin"
CACHE="$TOOLS/cache"

SHELLCHECK_VERSION="0.10.0"
SHELLCHECK_SHA256="6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87"

mkdir -p "$BIN" "$CACHE"

# deb_tool <package> <path-inside-package>
deb_tool() {
	local pkg="$1" path="$2" name
	name="$(basename "$path")"
	if [ -x "$BIN/$name" ]; then
		return 0
	fi
	if command -v "$name" > /dev/null 2>&1; then
		ln -sf "$(command -v "$name")" "$BIN/$name"
		return 0
	fi
	if ! command -v apt-get > /dev/null 2>&1 || ! command -v dpkg-deb > /dev/null 2>&1; then
		echo "error: $name is missing and apt-get/dpkg-deb are not available; install $pkg manually" >&2
		exit 1
	fi
	(cd "$CACHE" && rm -f "${pkg}"_*.deb && apt-get download -q "$pkg" > /dev/null)
	rm -rf "$TOOLS/pkg-$pkg"
	dpkg-deb -x "$CACHE/${pkg}"_*.deb "$TOOLS/pkg-$pkg"
	ln -sf "$TOOLS/pkg-$pkg/$path" "$BIN/$name"
}

shellcheck_tool() {
	if [ -x "$BIN/shellcheck" ] && "$BIN/shellcheck" --version | grep -q "version: $SHELLCHECK_VERSION"; then
		return 0
	fi
	local tarball="$CACHE/shellcheck-v$SHELLCHECK_VERSION.tar.xz"
	curl -sSfL --max-time 120 -o "$tarball" \
		"https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.linux.x86_64.tar.xz"
	echo "$SHELLCHECK_SHA256  $tarball" | sha256sum -c --quiet -
	tar -xJf "$tarball" -C "$TOOLS"
	ln -sf "$TOOLS/shellcheck-v$SHELLCHECK_VERSION/shellcheck" "$BIN/shellcheck"
}

deb_tool mksh bin/mksh
deb_tool bc usr/bin/bc
deb_tool xxd usr/bin/xxd
shellcheck_tool

echo "Tools in $BIN:"
printf '  mksh:       %s\n' "$("$BIN/mksh" -c 'echo $KSH_VERSION')"
printf '  shellcheck: %s\n' "$("$BIN/shellcheck" --version | sed -n 's/^version: //p')"
printf '  bc:         %s\n' "$("$BIN/bc" --version | head -1)"
printf '  xxd:        %s\n' "$("$BIN/xxd" -v 2>&1 | head -1)"
