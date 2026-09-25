# Sourced by every stub. journal <name> <args...> appends one tab-separated line to /sim/journal.
journal() {
	local IFS=$'\t'
	printf '%s\n' "$*" >> /sim/journal
}
PROFILE=/sim/profile
