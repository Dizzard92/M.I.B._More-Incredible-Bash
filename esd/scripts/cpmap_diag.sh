#!/bin/ksh

# esd cpmap_diag.sh v1.0.0 (2026-10-09 by Marco Nacken)

if [ -f /net/rcc/dev/shmem/backup.mib ] || [ -f /net/rcc/dev/shmem/reboot.mib ] || [ -f /net/rcc/dev/shmem/flash.mib ]; then
	echo "Some process is already running in background, don't interrupt!"
	exit 0
fi

trap '' 2

export PATH=.:/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/media/gracenote/bin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin
export LD_LIBRARY_PATH=/lib:/mnt/app/root/lib-target:/eso/lib:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib
unset LD_PRELOAD

export GEM=1
echo -ne "M.I.B. - More Incredible Bash "
cat /net/mmx/fs/sda0/VERSION
echo "NOT FOR COMMERCIAL USE - IF YOU BOUGHT THIS YOU GOT RIPPED OFF"
echo ""

SCRIPTS=/net/mmx/fs/sda0/mod/carplay_maps_vc
if [ ! -s "$SCRIPTS/cpmap_diag_core.sh" ]; then
	echo "FAIL: mod/carplay_maps_vc/cpmap_diag_core.sh was not found on SD media"
	trap 2
	exit 1
fi

/bin/ksh "$SCRIPTS/cpmap_diag_core.sh" /net/mmx/fs/sda0
rc=$?

trap 2

exit $rc
