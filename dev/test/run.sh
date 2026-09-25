#!/usr/bin/env bash
# Characterization ("golden master") tests: runs every scenario in dev/test/scenarios through the
# head-unit simulator and compares journal, stdout, log and changed files with the recorded goldens.
#
# Usage: dev/test/run.sh [--record] [--rev <commit>] [--jobs N] [--keep] [scenario-glob...]
#   --record        write the results as the new expected.* files instead of comparing
#   --rev <commit>  take the SD card content from a commit (use baseline/pre-refactor to record)
#   --jobs N        parallel scenarios (default: number of CPUs, at most 12)
#   --keep          keep simulator output of passing scenarios too
#   scenario-glob   e.g. 'flash_*' (default: all)
#
# Scenario folder dev/test/scenarios/<name>/:
#   cmd        shell command line run on the simulated unit with /bin/sh -c (required)
#   profile    simulator profile (default mhi2)       node     mmx or rcc (default mmx)
#   setup.sh   host-side preparation (see dev/sim/mibsim --help)
#   stdin      standard input                           timeout  seconds (default 300)
#   expected.{exit,stdout,journal,log,files}            the goldens

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SCEN="$TEST_DIR/scenarios"
PARTS=(exit stdout journal log files)

# --- one scenario (internal) ---------------------------------------------------------------------
if [ "${1:-}" = "--one" ]; then
	name="$2" runroot="$3" mode="$4" rev="$5" keep="$6"
	s="$SCEN/$name" w="$runroot/$name"
	rm -rf "$w"; mkdir -p "$w"
	args=(--out "$w/sim" --profile "$(cat "$s/profile" 2>/dev/null || echo mhi2)"
	      --node "$(cat "$s/node" 2>/dev/null || echo mmx)"
	      --timeout "$(cat "$s/timeout" 2>/dev/null || echo 300)")
	[ -n "$rev" ] && args+=(--rev "$rev")
	[ -f "$s/setup.sh" ] && args+=(--setup "$s/setup.sh")
	[ -f "$s/stdin" ] && args+=(--stdin "$s/stdin")
	if ! "$ROOT/dev/sim/mibsim" "${args[@]}" -- /bin/sh -c "$(cat "$s/cmd")" > "$w/mibsim.out" 2>&1; then
		echo "ERROR" > "$w/status"; exit 0
	fi
	"$TEST_DIR/normalize.sh" "$w/sim" "$w"
	if [ "$mode" = record ]; then
		for p in "${PARTS[@]}"; do cp "$w/actual.$p" "$s/expected.$p"; done
		echo "RECORDED" > "$w/status"
	else
		: > "$w/diff"
		for p in "${PARTS[@]}"; do
			diff -u --label "expected.$p" --label "actual.$p" "$s/expected.$p" "$w/actual.$p" >> "$w/diff" 2>&1 || true
		done
		if [ -s "$w/diff" ]; then echo "FAIL" > "$w/status"; else echo "PASS" > "$w/status"; fi
	fi
	if [ "$keep" != 1 ] && [ "$(cat "$w/status")" != FAIL ]; then rm -rf "$w/sim"; fi
	exit 0
fi

# --- driver --------------------------------------------------------------------------------------------
mode=compare rev="" jobs="$(nproc)" keep=0 patterns=()
[ "$jobs" -gt 12 ] && jobs=12
while [ $# -gt 0 ]; do
	case "$1" in
		--record) mode=record; shift ;;
		--rev) rev="$2"; shift 2 ;;
		--jobs) jobs="$2"; shift 2 ;;
		--keep) keep=1; shift ;;
		-h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) patterns+=("$1"); shift ;;
	esac
done
[ ${#patterns[@]} -gt 0 ] || patterns=('*')

names=()
for pat in "${patterns[@]}"; do
	for d in "$SCEN"/$pat; do
		[ -f "$d/cmd" ] && names+=("$(basename "$d")")
	done
done
[ ${#names[@]} -gt 0 ] || { echo "no scenarios match ${patterns[*]}" >&2; exit 2; }
mapfile -t names < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort -u)

runroot="$TEST_DIR/out/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$runroot"
ln -sfn "$(basename "$runroot")" "$TEST_DIR/out/latest"
start=$(date +%s)
printf '%s\n' "${names[@]}" | xargs -P "$jobs" -I{} "$0" --one {} "$runroot" "$mode" "$rev" "$keep"

passed=0 failed=0 recorded=0 errors=0
for n in "${names[@]}"; do
	st="$(cat "$runroot/$n/status" 2>/dev/null || echo ERROR)"
	case "$st" in
		PASS) passed=$((passed + 1)); echo "PASS  $n" ;;
		RECORDED) recorded=$((recorded + 1)); echo "REC   $n" ;;
		FAIL) failed=$((failed + 1)); echo "FAIL  $n"; sed 's/^/      /' "$runroot/$n/diff" | head -60 ;;
		*) errors=$((errors + 1)); echo "ERROR $n (see ${runroot#"$ROOT"/}/$n/mibsim.out)" ;;
	esac
done
echo "----"
if [ "$mode" = record ]; then
	echo "$recorded recorded, $errors errors ($(( $(date +%s) - start ))s)"
else
	echo "$passed passed, $failed failed, $errors errors ($(( $(date +%s) - start ))s)"
fi
[ "$failed" -eq 0 ] && [ "$errors" -eq 0 ]
