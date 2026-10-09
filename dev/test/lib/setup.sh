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

# cpmap_installed: CarPlay Maps VC as install-carplay-maps.sh leaves it on an MU1447 unit with a
# 790 cluster (sparse lsd.jxe of the MU1447 size, wrapper, jar, patched lsd.sh), an empty /ramdisk
# and a process list with the module's helpers for the pidin stub
cpmap_installed() {
	local app="$SIM_UNIT/mmx/mnt/app" payload="$SIM_SD/mod/carplay_maps_vc/payload"
	truncate -s 55712574 "$SIM_UNIT/mmx/ifs/lsd.jxe"
	mkdir -p "$app/carplaymaps/stock_first" "$app/carplaymaps/rollback" "$SIM_UNIT/mmx/ramdisk"
	echo "V7.2.2-PLAINTEXT-TOOLBOX-1" > "$app/carplaymaps/VERSION"
	echo "MU1447/790" > "$app/carplaymaps/PROFILE"
	touch "$app/carplaymaps/CLUSTER_AUTO_ENABLE"
	printf 'dio_manager' > "$app/carplaymaps/stock_first/dio_manager.real"
	cp "$payload/profiles/MU1447/790/core.so" "$app/carplaymaps/core.so"
	cp "$payload/common/dio_manager.wrapper.sh" "$app/eso/bin/apps/dio_manager"
	cp "$payload/common/CarPlayClusterControls.jar" "$app/eso/hmi/lsd/jars/CarPlayClusterControls.jar"
	printf '%s\n' '#!/bin/ksh' \
		'BOOTCLASSPATH=-Xbootclasspath/a:/ifs/lsd.jxe:/ifs/jre/lib/charconv.zip' \
		'BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$BASE_DIR/lsd/jars/CarPlayClusterControls.jar:$BASE_DIR/lsd/jars/NavActiveIgnore.jar"' \
		'$J9 $VMOPTIONS $BOOTCLASSPATH -jxe $HMI_JXE &' > "$app/eso/hmi/lsd/lsd.sh"
	cp "$app/eso/hmi/lsd/lsd.sh" "$app/carplaymaps/rollback/lsd.sh"
	printf '%s\n' '     pid Arguments' '       1 procnto-instr' \
		'   40977 /mnt/app/carplaymaps/stock_first/dio_manager.real' \
		'   41000 /mnt/app/carplaymaps/carplay-cluster-supervisor' \
		'   41001 /mnt/app/carplaymaps/altscreen-most-bridge' \
		'   41002 /mnt/app/carplaymaps/security_bridge/carplay-pairing-helper --server' \
		> "$SIM_OUT/sim/pidin.txt"
}

# cpmap_log <line>...: append lines to /ramdisk/carplaymaps-video.log (the core.so log)
cpmap_log() {
	printf '%s\n' "$@" >> "$SIM_UNIT/mmx/ramdisk/carplaymaps-video.log"
}
