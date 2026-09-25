#!/usr/bin/env bash
# normalize.sh <mibsim-result-dir> <dest-dir>
# Writes actual.{exit,stdout,journal,log,files} with run-dependent details removed:
# dd timing lines, "ls -l" dates/block counts/directory sizes, and the contents of files whose
# bytes contain such details (listed in VOLATILE below; only their existence is compared).

set -euo pipefail
src="$1" dst="$2"

text_filter() {
	sed -E \
		-e 's/^([0-9]+ bytes( \([^)]*\))?( \([^)]*\))? copied), .*/\1, <TIME>/' \
		-e 's/^ *([0-9]+ +)?([-dlcbps][-rwxsStT]{9}) +[0-9]+ +[^ ]+ +[^ ]+ +([0-9]+) +[A-Z][a-z]{2} +[0-9]+ +([0-9]{4}|[0-9]{2}:[0-9]{2}) +(.*)$/<ls> \2 \3 \5/' \
		-e 's/^<ls> (d[-rwxsStT]{9}) [0-9]+ /<ls> \1 <DIRSIZE> /' \
		-e 's/^total [0-9]+$/total <N>/'
}

# files whose content is inherently run-dependent (logs, listings with timestamps)
VOLATILE='(-LOG\.txt|/flash\.log|-folders\.txt|-Partition\.txt|-RCC-Flashlock\.log|\.log)$'

cp "$src/exit" "$dst/actual.exit"
text_filter < "$src/stdout" > "$dst/actual.stdout"
cp "$src/sim/journal" "$dst/actual.journal"
# The log also lists the SD card root with "ls -als" (config/LOGS). That listing is diagnostic
# and changes whenever a top-level file changes, so it is left out of the log comparison.
text_filter < "$src/log" | grep -vE '^(<ls> |total <N>$)' > "$dst/actual.log" || true

# changes with content hashes: "<op> <path> <sha1|<volatile>|<dir>>"
: > "$dst/actual.files"
while IFS= read -r line; do
	op="${line%% *}" path="${line#* }"
	if [ "$op" = "-" ]; then
		echo "- $path" >> "$dst/actual.files"
	elif [[ "$path" =~ $VOLATILE ]]; then
		echo "$op $path <volatile>" >> "$dst/actual.files"
	elif [[ "$path" == *" -> "* ]]; then
		echo "$op symlink $path" >> "$dst/actual.files"
	else
		echo "$op $path $(sha1sum < "$src/$path" | cut -c1-40)" >> "$dst/actual.files"
	fi
done < "$src/changes"
