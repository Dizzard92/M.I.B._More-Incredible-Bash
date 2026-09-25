#!/usr/bin/env bash
# Static checks for all head-unit shell sources (list: dev/tools/shell-sources.sh).
#
# 1. "mksh -n" syntax check. mksh is the reference for the QNX Korn shell; any error fails.
# 2. ShellCheck (-s ksh) compared against dev/lint/shellcheck-baseline.txt.
#    Findings are keyed by file, severity and message (line numbers are ignored so moving
#    code is not "new"). A key whose count rises fails the run; counts may only go down.
#
# Usage: dev/tools/lint.sh                    check
#        dev/tools/lint.sh --update-baseline  rewrite the baseline (only when findings went down,
#                                             or deliberately, with a Decision Log entry)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/dev/.tools/bin:$PATH"
BASELINE="dev/lint/shellcheck-baseline.txt"

for tool in mksh shellcheck; do
	if ! command -v "$tool" > /dev/null 2>&1; then
		echo "error: $tool not found - run dev/tools/install-deps.sh" >&2
		exit 1
	fi
done

mapfile -t FILES < <(dev/tools/shell-sources.sh)
status=0

# --- 1. syntax -------------------------------------------------------------
syntax_failed=0
for f in "${FILES[@]}"; do
	if ! out="$(mksh -n "$f" 2>&1)"; then
		echo "$out"
		syntax_failed=$((syntax_failed + 1))
	fi
done
if [ "$syntax_failed" -eq 0 ]; then
	echo "mksh -n: ${#FILES[@]} files OK"
else
	echo "mksh -n: $syntax_failed of ${#FILES[@]} files FAILED"
	status=1
fi

# --- 2. shellcheck ratchet ---------------------------------------------------
# gcc format: file:line:col: level: message [SCnnnn]  ->  file|level|message [SCnnnn]
current="$(shellcheck -s ksh -f gcc "${FILES[@]}" 2> /dev/null \
	| sed -E 's/^([^:]+):[0-9]+:[0-9]+: ([a-z]+): /\1|\2|/' | LC_ALL=C sort || true)"

if [ "${1:-}" = "--update-baseline" ]; then
	mkdir -p "$(dirname "$BASELINE")"
	printf '%s\n' "$current" > "$BASELINE"
	echo "shellcheck: baseline written ($(grep -c . "$BASELINE") findings)"
	exit "$status"
fi

if [ ! -f "$BASELINE" ]; then
	echo "error: $BASELINE missing - run dev/tools/lint.sh --update-baseline once" >&2
	exit 1
fi

report="$(awk -F'\t' '
	FNR == NR { base[$0]++; next }
	          { cur[$0]++ }
	END {
		for (k in cur) if (cur[k] > base[k]) { new += cur[k] - base[k]; printf "NEW (%d): %s\n", cur[k] - base[k], k }
		for (k in base) { total_base += base[k]; if (base[k] > cur[k]) fixed += base[k] - cur[k] }
		for (k in cur) total_cur += cur[k]
		printf "SUMMARY %d %d %d %d\n", total_cur, new, fixed, total_base
	}' "$BASELINE" <(printf '%s\n' "$current" | grep .))"

grep '^NEW' <<< "$report" | sed 's/|/: /; s/|/: /' || true
read -r _ total new fixed base <<< "$(grep '^SUMMARY' <<< "$report")"
echo "shellcheck: $total findings, $new new, $fixed fixed (baseline $base)"
if [ "$new" -gt 0 ]; then
	status=1
fi
if [ "$fixed" -gt 0 ] && [ "$new" -eq 0 ]; then
	echo "hint: findings went down - run dev/tools/lint.sh --update-baseline and commit the baseline"
fi

if [ "$status" -eq 0 ]; then
	echo OK
fi
exit "$status"
