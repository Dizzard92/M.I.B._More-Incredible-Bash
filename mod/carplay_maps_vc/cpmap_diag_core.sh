#!/bin/ksh

# Collects CarPlay Maps VC diagnostics into <sd-root>/backup/carplaymaps-diag/<timestamp>/.
# Read-only on the unit: only the SD card is remounted writable and written to.
# Usage: cpmap_diag_core.sh <sd-root>

SD="$1"

fail() {
    echo "CPMAP_DIAG_FAIL=$1"
    exit 1
}

if [ -z "$SD" ] || [ ! -d "$SD" ]; then
    fail "SD_NOT_FOUND"
fi

if [ -n "${CPMAP_TEST_ROOT:-}" ] && [ -d "$CPMAP_TEST_ROOT/mnt/app" ] && [ -s "$CPMAP_TEST_ROOT/ifs/lsd.jxe" ]; then
    MMX="$CPMAP_TEST_ROOT"
elif [ -d /mnt/app ] && [ -s /ifs/lsd.jxe ]; then
    MMX=""
elif [ -d /net/mmx/mnt/app ] && [ -s /net/mmx/ifs/lsd.jxe ]; then
    MMX="/net/mmx"
else
    fail "MMX_FILESYSTEM_NOT_FOUND"
fi

APP="$MMX/mnt/app"
JXE="$MMX/ifs/lsd.jxe"
RAM="$MMX/ramdisk"
ROOT="$APP/carplaymaps"
DIO="$APP/eso/bin/apps/dio_manager"
LSD="$APP/eso/hmi/lsd/lsd.sh"
JAR="$APP/eso/hmi/lsd/jars/CarPlayClusterControls.jar"
PAYLOAD_JAR="$SD/mod/carplay_maps_vc/payload/common/CarPlayClusterControls.jar"

if [ -x /net/rcc/usr/bin/date ]; then
    STAMP=$(/net/rcc/usr/bin/date +%Y_%m_%d_%H_%M_%S 2>/dev/null)
fi
[ -n "$STAMP" ] || STAMP=$(date +%Y_%m_%d_%H_%M_%S 2>/dev/null)
[ -n "$STAMP" ] || STAMP="unknown_time_$$"

[ -n "${CPMAP_TEST_ROOT:-}" ] || mount -uw "$SD" >/dev/null 2>&1
OUT="$SD/backup/carplaymaps-diag/$STAMP"
if ! mkdir -p "$OUT" 2>/dev/null || ! touch "$OUT/report.txt" 2>/dev/null; then
    fail "SD_NOT_WRITABLE"
fi
REPORT="$OUT/report.txt"

say() {
    echo "$1"
    echo "$1" >> "$REPORT"
}

size_of() {
    line=$(ls -ln "$1" 2>/dev/null) || { echo "-"; return; }
    # shellcheck disable=SC2086 # split the ls line into fields
    set -- $line
    echo "$5"
}

say "CarPlay Maps VC diagnostics $STAMP"
say "M.I.B. $(cat "$SD/VERSION" 2>/dev/null)"

JXE_SIZE=$(size_of "$JXE")
case "$JXE_SIZE" in
    55915411) MU="MU1102" ;;
    55840541) MU="MU1367" ;;
    55840933) MU="MU1440" ;;
    55712574) MU="MU1447" ;;
    *) MU="unsupported" ;;
esac
say "lsd.jxe size: $JXE_SIZE ($MU)"

say ""
say "== Installation"
if [ -s "$ROOT/VERSION" ]; then
    say "Version: $(cat "$ROOT/VERSION" 2>/dev/null)"
    say "Profile: $(cat "$ROOT/PROFILE" 2>/dev/null)"
else
    say "Status: not installed"
fi
if [ -e "$ROOT/CLUSTER_AUTO_ENABLE" ]; then
    say "CLUSTER_AUTO_ENABLE: yes"
else
    say "CLUSTER_AUTO_ENABLE: no"
fi
[ -e "$ROOT/stock_first/DISABLED" ] && say "stock_first/DISABLED: yes (cluster supervisor is off)"
if grep -q 'carplaymaps' "$DIO" 2>/dev/null; then
    say "dio_manager: CarPlay Maps VC wrapper"
else
    say "dio_manager: factory program (size $(size_of "$DIO"))"
fi
say "Control jar on unit: $(size_of "$JAR") bytes, on SD: $(size_of "$PAYLOAD_JAR") bytes"
JAR_REFS=$(grep -c 'CarPlayClusterControls.jar' "$LSD" 2>/dev/null)
JAR_REFS="${JAR_REFS:-0}"
say "lsd.sh mentions of the control jar: $JAR_REFS (expected 1)"
grep -n 'BOOTCLASSPATH=' "$LSD" 2>/dev/null | while read -r line; do
    say "  $line"
done

say ""
say "== Processes"
PROCS="$OUT/processes.txt"
if [ -n "${CPMAP_TEST_ROOT:-}" ]; then
    cp "$CPMAP_TEST_ROOT/pidin.txt" "$PROCS" 2>/dev/null
elif [ -n "$MMX" ]; then
    on -f mmx pidin arg > "$PROCS" 2>/dev/null
else
    pidin arg > "$PROCS" 2>/dev/null
fi
if [ -s "$PROCS" ]; then
    for name in dio_manager carplay-cluster-supervisor altscreen-most-bridge carplay-pairing-helper; do
        if grep -q "$name" "$PROCS"; then
            say "$name: running"
        else
            say "$name: NOT running"
        fi
    done
else
    say "Process list not available"
fi

LOG="$RAM/carplaymaps-video.log"
[ -s "$LOG" ] || LOG="$RAM/carplay_altscreen_handshake/handshake.log"

count() {
    n=$(grep -c "event=$1" "$LOG" 2>/dev/null)
    echo "${n:-0}"
}

say ""
say "== core.so events ($(basename "$LOG"))"
if [ -s "$LOG" ]; then
    LOADED=$(count 'altscreen-handshake-probe-loaded ')
    VIDEO=$(count 'alt-video-connected ')
    SESSION=$(count 'map-control-session-remembered ')
    PORT_OK=$(count 'map-control-loopback-ready ')
    PORT_FAIL=$(( $(count 'map-control-socket-failed ') + $(count 'map-control-bind-failed ') ))
    REQUEST=$(count 'map-control-command-request ')
    NO_SESSION=$(count 'map-control-no-session ')
    UNKNOWN=$(count 'map-control-unknown-command ')
    ANSWER=$(count 'alt-command-completion-')
    say "core.so loaded:          $LOADED"
    say "cluster video connected: $VIDEO"
    say "CarPlay session saved:   $SESSION"
    say "port 7032 ready/failed:  $PORT_OK/$PORT_FAIL"
    say "zoom/map commands sent:  $REQUEST"
    say "commands w/o session:    $NO_SESSION"
    say "unknown commands:        $UNKNOWN"
    say "iPhone answers:          $ANSWER"
    say "Last map control lines:"
    grep -e 'event=map-control' -e 'event=alt-command-completion' "$LOG" 2>/dev/null | tail -n 10 | while read -r line; do
        say "  $line"
    done
else
    say "No runtime log in /ramdisk"
fi

say ""
say "== Verdict"
if [ ! -s "$LOG" ]; then
    say "No core.so log since the last start: CarPlay was not connected,"
    say "or dio_manager did not start with core.so."
elif [ "$PORT_OK" -eq 0 ]; then
    say "core.so did not open the zoom command port 7032."
elif [ "$JAR_REFS" -ne 1 ]; then
    say "lsd.sh does not load CarPlayClusterControls.jar exactly once,"
    say "so steering-wheel keys cannot reach core.so."
elif [ "$REQUEST" -eq 0 ] && [ "$NO_SESSION" -eq 0 ] && [ "$UNKNOWN" -eq 0 ]; then
    say "No steering-wheel command reached core.so. The jar only reacts to"
    say "keyboard 4, keys 38/39 (KEY_MFW_UP/DOWN): this wheel sends other codes"
    say "or the keys do not reach the head unit while the cluster shows the map."
elif [ "$REQUEST" -eq 0 ]; then
    say "Commands reached core.so but none was sent: no CarPlay session"
    say "or unknown command text (see counts above)."
else
    say "$REQUEST command(s) were sent to the iPhone. If the map still does not"
    say "zoom, check the iPhone answers above and the navigation app."
fi

# Supporting files. Pairing/session logs and binary captures are left out on purpose.
cp "$LSD" "$OUT/lsd.sh" 2>/dev/null
ls -lR "$ROOT" > "$OUT/carplaymaps-files.txt" 2>&1
ls -l "$RAM" > "$OUT/ramdisk-files.txt" 2>&1
for f in carplaymaps-video.log carplaymaps-launcher.log carplay-cluster-supervisor.log altscreen-most-bridge.log carplaymaps-keys.log; do
    [ -f "$RAM/$f" ] && cp "$RAM/$f" "$OUT/$f" 2>/dev/null
done
for dir in carplay_altscreen_handshake carplaymaps-diagnostics; do
    for f in "$RAM/$dir"/*.log; do
        [ -f "$f" ] && cp "$f" "$OUT/$dir-${f##*/}" 2>/dev/null
    done
done

sync 2>/dev/null || true
say ""
say "Saved to: backup/carplaymaps-diag/$STAMP"
echo "CPMAP_DIAG_OK"
exit 0
