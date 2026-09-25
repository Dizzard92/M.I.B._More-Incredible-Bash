#!/usr/bin/env bash
# Generates the table-driven scenarios in dev/test/scenarios (idempotent; goldens are kept):
#   menu_<variant>_<script>   every script entry of esd/Launcher-sda0.esd (variant mhi2, profile mhi2)
#                             and esd/Launcher-MHIG-sda0.esd (variant mhig, profile mhig)
#   start_<option>            every option of the interactive "start" menu (node rcc), then "q"
#   lock_<script>             every menu wrapper that checks flash.mib, started while flash.mib exists
# Hand-written scenarios (flash_*, backup_*, ...) are not touched.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCEN="$ROOT/dev/test/scenarios"
cd "$ROOT"

put() { # put <scenario> <file> <content>
	mkdir -p "$SCEN/$1"
	printf '%s\n' "$3" > "$SCEN/$1/$2"
}

for pair in "mhi2:esd/Launcher-sda0.esd" "mhig:esd/Launcher-MHIG-sda0.esd"; do
	variant="${pair%%:*}" esd="${pair#*:}"
	for script in $(grep -oE 'esd/scripts/[A-Za-z0-9_]+\.sh' "$esd" | LC_ALL=C sort -u); do
		name="menu_${variant}_$(basename "$script" .sh)"
		put "$name" cmd "/net/mmx/fs/sda0/$script"
		put "$name" profile "$variant"
	done
done

for opt in 0 1 2 3 4 5 6 7 8 9 F G O U W R C S H L X; do
	name="start_$opt"
	put "$name" cmd "/net/mmx/fs/sda0/start"
	put "$name" node rcc
	put "$name" stdin "$(printf '%s\nq' "$opt")"
done

for script in $(grep -l 'shmem/flash.mib' esd/scripts/*.sh | LC_ALL=C sort); do
	name="lock_$(basename "$script" .sh)"
	put "$name" cmd "/net/mmx/fs/sda0/$script"
	put "$name" setup.sh 'touch "$SIM_UNIT/rcc/dev/shmem/flash.mib"'
done

echo "$(ls "$SCEN" | wc -l) scenarios in ${SCEN#"$ROOT"/}"
