#!/usr/bin/env bash
# Prints the repository-relative path of every shell source that runs on the head unit,
# one per line, sorted. Used by lint.sh and CI. Run from anywhere.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

{
	echo start
	find apps -maxdepth 1 -type f
	for f in BASICS GLOBALS LOCALS LOGS MIBCHECK USB; do echo "config/$f"; done
	ls esd/scripts/*.sh
	echo Launcher/stuff.sh
	echo Launcher/final/finalScript.sh
	echo mod/custom.sh
	ls mod/sshd/scripts/*.sh
	echo mod/sshd/scp_wrapper
	echo mod/sshd/usr/sbin/start_sshd
	[ -d lib ] && find lib -type f -name '*.sh'
	true
} | LC_ALL=C sort -u
