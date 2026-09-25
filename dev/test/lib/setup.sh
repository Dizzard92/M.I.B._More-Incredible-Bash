# Helpers for scenario setup.sh files. Source with:
#   . "$(dirname "${BASH_SOURCE[0]}")/../../lib/setup.sh"
# Available variables: SIM_SD, SIM_UNIT, SIM_PROFILE, PROFILE_* (see dev/sim/mibsim --help).

# place_patch_folder [header] [image]: pre-made MHI2 patch as users copy it to the SD card
place_patch_folder() {
	local header="${1:-$PROFILE_HEADER}" image="${2:-$SIM_PROFILE/stage2-patched.ifs}"
	local d="$SIM_SD/patches/${PROFILE_TRAIN}_${PROFILE_MU}_PATCH"
	mkdir -p "$d"
	cp "$image" "$d/${PROFILE_MU}-ifs-root-part2-0x00${PROFILE_OFFSET}-${header}.ifs"
}

# flash_image <image>: write an image into the unit's RCC flash at the stage-2 offset and make
# the flashlock listing report its size
flash_image() {
	local image="$1" size
	size=$(stat -c %s "$image")
	dd if="$image" of="$SIM_UNIT/rcc/dev/fs0" bs=4096 seek=$(( 0x$PROFILE_OFFSET / 4096 )) conv=notrunc status=none
	if [ -f "$SIM_PROFILE/flashlock.txt" ]; then
		sed -i -E "s/^( 3 image type=2\(IFS     \) $PROFILE_OFFSET len \()[0-9]+\)/\1$size)/" "$SIM_PROFILE/flashlock.txt"
	fi
}

# lock <name>: create /net/rcc/dev/shmem/<name>.mib
lock() {
	touch "$SIM_UNIT/rcc/dev/shmem/$1.mib"
}
