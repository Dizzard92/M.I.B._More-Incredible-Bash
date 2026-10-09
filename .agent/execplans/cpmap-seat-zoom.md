# Make the steering-wheel zoom of CarPlay Maps VC work on a Seat Leon 5F (MU1447, 790 cluster)

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.agent/PLANS.md` (repository-relative path). Read that file before editing this plan. It builds on `.agent/execplans/mib-refactor.md`, which is checked in; only the parts of that plan that matter here are repeated below, so this plan can be followed on its own.


## Purpose / Big Picture

M.I.B. ("More Incredible Bash") is a set of shell scripts that people copy to an SD card and run on the infotainment head unit of Volkswagen-group cars. Since release V3.8.0 it contains a third-party module called "CarPlay Maps VC". The module shows the Apple CarPlay map on the digital instrument cluster (the "virtual cockpit", VC). It also lets the driver zoom the map and switch the map view with the steering-wheel buttons. The module was written by omonob for VW and Škoda cars. The M.I.B. maintainer added a profile for Seat units with firmware MU1447.

The owner of this repository drives a Seat Leon 5F (third-generation Leon, MQB platform) with an MHI2 head unit on firmware MU1447 and a 10.25-inch digital cluster. In the module and its menu, this cluster is called "790" or "AID 10.5" ("AID" means Active Info Display). He installed the module on 2026-10-09 with the menu entry "Install 790 AID 10.5 (AUTO MU)". The CarPlay map appears on the cluster with Apple Maps, but **the map cannot be zoomed with the steering wheel**.

After this plan, the owner can zoom and switch the CarPlay map on his cluster with the steering wheel. He can also see where the chain breaks, without a laptop: a menu entry writes a diagnostic report to the SD card and shows a one-line verdict on screen. Any other Seat (or VW/Škoda) user with the same symptom can use the same entry, and the findings can be reported upstream.

The work has four steps. Each step can be checked on its own. First, a diagnostics menu entry (Milestone 1). Second, one test drive that runs it and records the verdict (Milestone 2). Third, if the verdict says the button presses never reach the module, a debug build of the module's Java part that records which key codes the Seat steering wheel really sends (Milestone 3). Fourth, the actual fix, and reporting it upstream (Milestone 4).


## Progress

- [x] (2026-10-09 19:30Z) Analysed the module end to end: the Java classes in `CarPlayClusterControls.jar` (disassembled), the ARM library `core.so` (disassembled; it is not stripped), the runtime wrapper, the issues of the original project, and the constants in the Java ROM image `lsd.jxe` from an M.I.B. backup of the owner's unit. Findings are in `Context and Orientation` and `Surprises & Discoveries`.
- [x] (2026-10-09 19:40Z) Created branch `cpmap/zoom-diagnose` from `refactor/core` (`6a5bd10`). Put the three small analysis helpers into `dev/tools/re/` (see `Interfaces and Dependencies`).
- [x] (2026-10-09 19:45Z) Wrote this ExecPlan.
- [x] (2026-10-09 21:20Z) Milestone 1: `mod/carplay_maps_vc/cpmap_diag_core.sh`, `esd/scripts/cpmap_diag.sh`, the menu entry plus hint line in `esd/Launcher-sda0.esd` (CRLF kept), the simulator stub `dev/sim/stubs/boot/pidin`, the setup helpers `cpmap_installed` and `cpmap_log` in `dev/test/lib/setup.sh`, and four scenarios with goldens: `menu_mhi2_cpmap_diag` (not installed), `lock_cpmap_diag` (generated), `cpmap_diag_mhi2_no_command` (the Seat symptom) and `cpmap_diag_mhi2_command_sent`. `dev/test/run.sh 'cpmap_diag_*' menu_mhi2_cpmap_diag lock_cpmap_diag` gives `4 passed`. `shellcheck -s ksh` on the core script is clean, `mksh -n` passes, and the error paths `SD_NOT_FOUND`, `SD_NOT_WRITABLE` and `MMX_FILESYSTEM_NOT_FOUND` were checked on the host with `CPMAP_TEST_ROOT`.
- [ ] NEXT: Milestone 2. The owner copies this branch's SD content to the card and follows the procedure in `Validation and Acceptance`.
- [ ] Milestone 2: owner runs the entry in the car following the procedure in `Validation and Acceptance`; the verdict and the report are recorded in `Surprises & Discoveries`.
- [ ] Milestone 3 (only if Milestone 2 says "no command reached core.so"): debug jar that logs every steering-wheel key event; owner presses every button once; the key codes are recorded.
- [ ] Milestone 4: fix (most likely: accept the Seat key codes in the Java filter), verified in the car; upstream report to omonob/MHI2-Carplay-Maps and Mr-MIBonk/M.I.B.


## Surprises & Discoveries

- Observation: the zoom is a four-stage chain. Every stage except the first is generic and identical for all brands. (1) The head unit's Java user interface, called "lsd", receives steering-wheel button events. The module puts its own copy of the class `de.esolutions.fw.dsi.keypanel.DSIKeyPanelDispatcher` in front of the factory class. Its `updateKey2` calls `de.vw.mib.carplay.clustercontrol.Mhi2ClusterControlBridge.onKey2(keyboard, key, state, ...)` before it forwards the event as usual. (2) `onKey2` returns immediately unless `keyboard == 4` and `key` is 38 or 39. (3) A short press of 38 sends the text `zoom-in` as a UDP datagram to `127.0.0.1:7032`, a short press of 39 sends `zoom-out`. Holding a key for 2,500 ms sends `map-previous` (38) or `map-next` (39). (4) `core.so` runs inside the CarPlay process `dio_manager`. Its thread `map_control_command_worker` receives the datagram. It sends the CarPlay command `changeMapZoomLevel` with `zoomDirection` 0 (in) or 1 (out) through the saved CarPlay session to the iPhone.
  Evidence: `python3 -I dev/tools/re/jdis.py` on the classes of `mod/carplay_maps_vc/payload/common/CarPlayClusterControls.jar`, specifically `Mhi2ClusterControlBridge.onKey2` (`iload_0; iconst_4; if_icmpeq`, `bipush 38`, `bipush 39`), `commandFor` (strings `zoom-in`, `zoom-out`, `map-previous`, `map-next`), `commandLoop` (`sipush 7032`, `"127.0.0.1"`), `Mhi2ClusterKeyState.LONG_PRESS_MILLIS = 2500`. `armdis.py` on `core.so`: `map_control_command_worker` binds port `0x1b78` (7032). It compares the received text with `map-next`, `map-previous`, `zoom-in` and `zoom-out`. It calls `send_map_semantic_command`, which builds `{type: changeMapZoomLevel, params: {uuid: b7e6c5a0-2222-4000-8000-000000000002, zoomDirection: 0|1}}` and calls `AirPlayReceiverSessionSendCommand`.

- Observation: in the owner's Seat firmware, the steering-wheel keyboard (`KBD_MFW`) is number 4. `KEY_MFW_UP` is 38 and `KEY_MFW_DOWN` is 39, which are the only codes the module accepts. The firmware also defines other arrow-like keys that the module ignores: `KEY_MFW_ARROW_A_UP` 46, `KEY_MFW_ARROW_A_DOWN` 47, `KEY_MFW_ARROW_B_UP` 48, `KEY_MFW_ARROW_B_DOWN` 49, `KEY_MFW_ARROW_RIGHT` 36, `KEY_MFW_ARROW_LEFT` 37, `KEY_MFW_ROLLER_LEFT` 40, `KEY_MFW_ROLLER_RIGHT` 44, `KEY_MFW_MENU` 35, `KEY_MFW_CANCEL` 41. A short form of this list is in `Artifacts and Notes`. A static analysis cannot tell which code the physical up/down buttons of a Leon 5F produce. That mapping happens in native code before Java sees the event. Leading hypothesis: the Seat wheel reports `ARROW_A`/`ARROW_B` (46 to 49) instead of `UP`/`DOWN`, so stage 2 drops every press silently. Alternative hypothesis: the cluster consumes the arrow buttons while it shows the map, and the head unit never sees them. Upstream issue #9 reports this symptom on a VW Golf 7.5: the cluster's scale display changes, the map does not.
  Evidence: `python3 dev/tools/re/j9const.py <lsd.jxe> 'KEY_MFW_[A-Z0-9_]+|KBD_[A-Z0-9_]+'` on `MU1409-lsd.jxe` from the owner's own M.I.B. backup (train `MHI2_ER_SEG11_P4708_1`, before the owner updated to MU1447; the backup is stored outside the repository because it contains the unit's serial number). The values come from the `DSIKeyPanel` constant set, the one where `KBD_MFW = 4`. A second, older set in the same image (`KBD_MFW = 2`, `KEY_MFW_ARROW_A_UP = 9`) belongs to another interface and is not the one `updateKey2` uses.

- Observation: `core.so` does not write to `/ramdisk/carplay_altscreen_handshake/handshake.log`, even though that path is the obvious string in the binary. Its function `log_path` first reads the environment variable `CARPLAY_ALTSCREEN_LOG`. The wrapper `mod/carplay_maps_vc/payload/common/dio_manager.wrapper.sh` sets it to `/ramdisk/carplaymaps-video.log`. So all events, including `map-control-*`, go to `/ramdisk/carplaymaps-video.log`. Every line has the form `t_us=<microseconds> pid=<pid> event=<name> ...`.
  Evidence: `armdis.py core.so log_path`: `getenv("CARPLAY_ALTSCREEN_LOG")`, and the default path is used only when the variable is empty.

- Observation: `core.so`'s `log_status` has a re-entrancy flag. If another thread is writing a log line at the same moment, the new line is silently dropped. A single missing `map-control-command-request` line therefore proves nothing. Several button presses with none logged do.
  Evidence: `armdis.py core.so log_status`: it loads a global flag, returns immediately if it is set, sets it, writes, and clears it again.

- Observation: `core.so` is byte-identical for all "790" profiles: MU1102, MU1367, MU1440 and the M.I.B.-added MU1447 (SHA-256 `a4bb6ce6e9e6…`). It has no brand- or firmware-specific logic. The "791" variant only adds an unused virtual HID knob device (input file `/mnt/app/carplaymaps/alt-knob.command`). So the MU1447 profile choice cannot cause the zoom problem. The map video works on the owner's car, which proves stages 3 and 4 can run there.
  Evidence: `sha256sum mod/carplay_maps_vc/payload/profiles/*/*/core.so`; `comm` of the `strings` of both variants.

- Observation: the module's own `DSIKeyPanelDispatcher` has the same 21 methods as the interface the factory Seat code implements. A mismatch would break all steering-wheel buttons, which the owner did not report.
  Evidence: `jdis.py` method list (`updateKey2`, `updateEncoder2`, …, `updateInputPanelReady`, `getProperty`, `asyncException`, `yyIndication`); the names `ATTRIBUTE_ID_DSIKEYPANEL_*` in the Seat `lsd.jxe` match.

- Observation: upstream reports useful for interpretation (omonob/MHI2-Carplay-Maps). Issue #1 says zoom works with Apple Maps and Google Maps but not with Waze, and that wireless CarPlay adapters can break the cluster map. Issue #9 (VW Golf 7.5): "When I press up or down, the distance numbers change, but the image stays static". Issue #8: the installer needs a line `BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:` in `lsd.sh`, which only exists after "NavActiveIgnore" was installed. The project README names only VW and Škoda.
  Evidence: `gh api repos/omonob/MHI2-Carplay-Maps/issues/<n>` and `.../comments` on 2026-10-09.


## Decision Log

- Decision: of the ten scenarios that `dev/test/gen-scenarios.sh` created for the cpmap menu entries, only `menu_mhi2_cpmap_diag` and `lock_cpmap_diag` are kept on this branch. The eight for the existing entries (`status`, `install_790`, `install_791`, `restore`, as `menu_mhi2_*` and `lock_*`) were deleted.
  Rationale: those eight belong to the item "Re-baseline on V3.8.0" in `mib-refactor.md`. They should be recorded together with the version-text normalisation planned there. Running the generator again recreates them, which is harmless.
  Date/Author: 2026-10-09, Claude.

- Decision: the simulator gets a general `pidin` stub (`dev/sim/stubs/boot/pidin`). It prints `/sim/pidin.txt` if a scenario provides one, or else a fixed minimal list.
  Rationale: no existing M.I.B. script calls `pidin`, so no golden changes. The stub lets scenarios describe which processes run. `CPMAP_TEST_ROOT` mode instead reads `<test-root>/pidin.txt`.
  Date/Author: 2026-10-09, Claude.

- Decision: the new core script uses `$(...)` and `if` blocks, unlike the backticks in the other cpmap scripts, so that it is ShellCheck-clean. QNX's Korn shell supports `$(...)`, which `config/GLOBALS` already uses.
  Rationale: new code should not add to the lint baseline.
  Date/Author: 2026-10-09, Claude.

- Decision: diagnose first, then fix. Milestone 1 builds a read-only diagnostics entry instead of guessing a fix.
  Rationale: the static analysis narrows the cause to stage 1 or 2 but cannot decide between "wrong key code" and "key never arrives". A wrong guess (for example a Seat jar that accepts 46 to 49) would mean editing a vendored binary for nothing. One test drive with the diagnostics entry decides it.
  Date/Author: 2026-10-09, Claude with the owner.

- Decision: the diagnostics entry never changes the unit. It only reads files and process lists on the unit and writes below `backup/carplaymaps-diag/<timestamp>/` on the SD card. The only "change" command it runs is `mount -uw` on the SD card, as `esd/scripts/tones.sh` already does.
  Rationale: anyone with a problem should be able to run it at any time without risk, also on cars where the module is not installed.
  Date/Author: 2026-10-09, Claude.

- Decision: the report leaves out the module's pairing and session logs (`/ramdisk/carplay-maps-session.log`, `/ramdisk/carplay_security_bridge/`) and all binary captures (`*.bin`, including the ring buffer `/ramdisk/carplay-alt-ring.bin`).
  Rationale: the pairing logs may contain material from the CarPlay pairing and session, and the zoom diagnosis does not need them. Users are likely to post the report publicly in an issue. The ring buffer is large video data and useless here.
  Date/Author: 2026-10-09, Claude.

- Decision: the new scripts live next to the module's own M.I.B. wrappers (`esd/scripts/cpmap_*.sh`, `mod/carplay_maps_vc/cpmap_*.sh`) and follow their style: self-contained `ksh`, no use of `config/GLOBALS`, the `CPMAP_TEST_ROOT` test hook, and `CPMAP_DIAG_OK` / `CPMAP_DIAG_FAIL=<reason>` result lines. Nothing under `mod/carplay_maps_vc/payload/` changes.
  Rationale: `mib-refactor.md` treats the payload as a vendored black box. The cpmap wrappers are self-contained so that they can be reused in the module's own toolbox.
  Date/Author: 2026-10-09, Claude.

- Decision: work happens on branch `cpmap/zoom-diagnose`, created from `refactor/core`, so the head-unit simulator and test runner in `dev/` are available. The two new scenarios get goldens recorded on the working tree, not on the tag `baseline/pre-refactor`, because the behaviour is new.
  Rationale: the refactor plan's goldens describe old behaviour. New features have no baseline to compare against.
  Date/Author: 2026-10-09, Claude.


## Outcomes & Retrospective

Milestone 1 (2026-10-09): the diagnostics entry exists and is covered by four simulator scenarios. On the simulated "Seat symptom" (module installed, video running, no command logged), it prints the verdict "No steering-wheel command reached core.so…". On a log with two commands, it prints "2 command(s) were sent to the iPhone…". What it does on the real unit is still unproven. `pidin arg` output, QNX `grep -c`/`tail -n` and the remount of the SD card are assumptions until Milestone 2.


## Context and Orientation

Terms used in this plan:

- Head unit / MU: the infotainment computer. It has two processors, each running the QNX operating system. The "MMX" runs the user interface and CarPlay. The "RCC" runs low-level services. Each sees the other's files below `/net/mmx/...` and `/net/rcc/...`. "MU1447" is the firmware release number. A unit's release is recognised from the exact size of `/ifs/lsd.jxe` (55712574 bytes for MU1447).
- lsd / `lsd.jxe`: the Java user interface of the head unit and its packed class image ("J9 ROM image"). It is started by the shell script `/mnt/app/eso/hmi/lsd/lsd.sh`. A line of the form `BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:<jar>:..."` in that script puts extra jars in front of the factory classes, so classes in those jars replace factory classes of the same name.
- GEM / ESD: the head unit's hidden "green engineering menu". M.I.B. adds screens to it with the text files `esd/Launcher-sda0.esd` (MHI2 units) and `esd/Launcher-MHIG-sda0.esd` (MHIG units). They use CRLF line endings. An entry `script` / `value sys 1 0x0100 "<path>"` runs a shell script and shows what it prints. `keyValue` entries with a `label` are plain text lines.
- MFL / MFW: the multifunction steering wheel. In the Java code its buttons arrive as keyboard `KBD_MFW` (4) with key codes `KEY_MFW_*`.
- dio_manager: the head unit process that runs CarPlay. The module replaces `/mnt/app/eso/bin/apps/dio_manager` with a wrapper script. The wrapper starts helper processes and then runs the saved factory program with `LD_PRELOAD=core.so:...`. `LD_PRELOAD` makes the system load `core.so` into the program, where it replaces some library functions.
- `/ramdisk`: a RAM file system on the MMX. It is emptied at every start, so logs must be collected before the unit is switched off.

Files of the module in this repository: `mod/carplay_maps_vc/payload/` (vendored, not to be edited), `mod/carplay_maps_vc/cpmap_common.sh` (finds the payload on the SD card and detects the MU), `mod/carplay_maps_vc/cpmap_restore_core.sh`, and the menu wrappers `esd/scripts/cpmap_status.sh`, `cpmap_install_790.sh`, `cpmap_install_791.sh` and `cpmap_restore.sh`. Their menu block starts at the comment `# Main -> M.I.B. -> CarPlay Maps VC by omonob (QCDWJ)` in `esd/Launcher-sda0.esd`. The installer `mod/carplay_maps_vc/payload/common/install-carplay-maps.sh` creates, on the unit:

    /mnt/app/carplaymaps/            VERSION, PROFILE, CLUSTER_AUTO_ENABLE, core.so, dio_manager.wrapper.sh,
                                     altscreen-most-bridge, carplay-cluster-supervisor, libcarplay-security-bridge.so,
                                     security_bridge/, stock_first/dio_manager.real, rollback/lsd.sh, rollback/...
    /mnt/app/eso/bin/apps/dio_manager      the wrapper (a text script that mentions /mnt/app/carplaymaps)
    /mnt/app/eso/hmi/lsd/jars/CarPlayClusterControls.jar
    /mnt/app/eso/hmi/lsd/lsd.sh            exactly one mention of CarPlayClusterControls.jar on the "/p:" line

At run time these files appear in `/ramdisk`: `carplaymaps-launcher.log` (wrapper), `carplaymaps-video.log` (`core.so`, the important one), `carplay-cluster-supervisor.log`, `altscreen-most-bridge.log`, the folder `carplaymaps-diagnostics/`, and `carplay_altscreen_handshake/` (captures). `carplay-cluster-supervisor` does nothing if `/mnt/app/carplaymaps/stock_first/DISABLED` exists or `CLUSTER_AUTO_ENABLE` is missing.

The `core.so` events that matter for zoom: `map-control-loopback-ready` (port 7032 is open), `map-control-socket-failed` / `map-control-bind-failed` (it is not), `map-control-session-remembered` / `map-control-session-forgotten` (a CarPlay session started or ended), `map-control-command-request` (a zoom or map command was sent to the iPhone), `map-control-no-session` (a command arrived without a session), `map-control-unknown-command`, `alt-command-completion-<status>` (the iPhone's answer), `alt-video-connected` (the cluster video stream started).

Developer tooling (runs on a Linux PC only; `dev/` is not packaged): `dev/sim/mibsim` runs any M.I.B. script against a simulated unit inside a chroot. The SD card is at `/net/mmx/fs/sda0`, `/net/rcc/usr/bin/date` always prints 2026-01-01 00:00:00 UTC, `/bin/sh` and `/bin/ksh` are `mksh`, and QNX tools such as `on`, `mount` and `slay` are stubs that record "unit-changing" calls in a journal. In the simulator, `/mnt/app` does not exist locally, only below `/net/mmx/`. `dev/test/run.sh [glob]` runs the scenarios in `dev/test/scenarios/<name>/`. Each scenario has `cmd`, optional `profile`, `node` and `setup.sh`, and the goldens `expected.*`. It compares results with the goldens. `--record` writes the goldens. `dev/test/gen-scenarios.sh` creates a `menu_mhi2_<script>` scenario for every script in the MHI2 menu file. `dev/tools/lint.sh` runs ShellCheck and fails on findings that are not in `dev/lint/shellcheck-baseline.txt`. `dev/tools/install-deps.sh` installs `mksh` and `shellcheck` into `dev/.tools/bin`.


## Plan of Work

Milestone 1 (diagnostics entry). Create `mod/carplay_maps_vc/cpmap_diag_core.sh`, a `#!/bin/ksh` script that takes the SD card root as its only argument. It finds the MMX file system the same way `cpmap_restore_core.sh` does: `$CPMAP_TEST_ROOT`, else local `/mnt/app` with `/ifs/lsd.jxe`, else `/net/mmx/...`. It makes the SD card writable and creates `<sd>/backup/carplaymaps-diag/<timestamp>/`, using `/net/rcc/usr/bin/date +%Y_%m_%d_%H_%M_%S` with plain `date` as fallback. Everything it prints is also appended to `report.txt` in that folder. It reports, in this order:

- The M.I.B. version and the `lsd.jxe` size with the MU it maps to.
- Whether the module is installed: `VERSION`, `PROFILE`, `CLUSTER_AUTO_ENABLE`, `stock_first/DISABLED`, whether `dio_manager` is the wrapper, the size of the installed jar against the payload jar, the number of jar mentions in `lsd.sh`, and the `BOOTCLASSPATH` lines.
- Whether `dio_manager`, `carplay-cluster-supervisor`, `altscreen-most-bridge` and `carplay-pairing-helper` run, from `on -f mmx pidin arg`, or "unknown" if `pidin` is missing.
- The counts of the `core.so` events listed above in `/ramdisk/carplaymaps-video.log`, with `handshake.log` as fallback.
- The last ten `map-control`/`alt-command-completion` lines.
- A verdict.

The verdict is the first matching case of the following:

- No runtime log: CarPlay was not connected since the start, or `core.so` did not load.
- Port not open.
- The jar is not in `lsd.sh` exactly once.
- No command reached `core.so`: the key filter or the key path is the cause. This is Milestone 3.
- Commands without a session.
- Commands sent: look at the iPhone's answers.

It then copies `lsd.sh`, a listing of `/mnt/app/carplaymaps` and `/ramdisk`, the full process list, and the allowed logs into the folder. Finally it prints `CPMAP_DIAG_OK` and the folder. Create `esd/scripts/cpmap_diag.sh` with the same header as `cpmap_status.sh`, which runs the core script with `/net/mmx/fs/sda0` and passes its exit code on. In `esd/Launcher-sda0.esd`, add after the "Show CarPlay Maps VC status" entry a `script` entry "Save CarPlay Maps VC diagnostics to SD" and a `keyValue` hint "Before: connect iPhone by cable, show map in VC, press up/down". Keep CRLF. Run `dev/test/gen-scenarios.sh`, which adds `menu_mhi2_cpmap_diag` (module not installed). Write the hand-made scenario `cpmap_diag_mhi2_installed`, whose `setup.sh` builds an installed module and a `/ramdisk` with a sample log that has key presses but no command. Record the goldens of both and check the reports.

Milestone 2 (test drive) is done by the owner, see `Validation and Acceptance`. The result decides Milestone 3 or 4.

Milestone 3 (key-code logging) is only needed if the verdict is "no command reached core.so". It needs a JDK 8, because the module's classes are class-file version 48 (Java 1.4) and were built with JDK 1.8.0_202. A JDK can be unpacked into `dev/.tools/` without root. Write a replacement `Mhi2ClusterControlBridge` with the same public method `onKey2(int,int,int,int,int)` that appends `keyboard key state` for every call to `/ramdisk/carplaymaps-keys.log` and otherwise behaves like the original. Build it with `-source 1.4 -target 1.4`. Pack it with the unchanged `DSIKeyPanelDispatcher.class` and `Mhi2ClusterKeyState.class` into a debug jar. Install it with a separate menu entry that only swaps the jar file and keeps the original next to it, plus an entry that restores the original. The owner then presses every steering-wheel button once while the map is shown, and runs the diagnostics again, which must also copy `carplaymaps-keys.log`.

Milestone 4 (fix). Depending on Milestone 2 and 3, either change the accepted key codes in the Java filter (for example 38/46/48 for "up" and 39/47/49 for "down"), build that jar as an M.I.B.-side variant and select it in `cpmap_install_790.sh` for MU1447, or document that the key never reaches the head unit on this car. Record the choice in the Decision Log, test in the car, and report upstream with the evidence.


## Concrete Steps

All commands run from the repository root `/home/marco/Code/mibfork` on branch `cpmap/zoom-diagnose`.

    dev/tools/install-deps.sh                # once; mksh and shellcheck into dev/.tools/bin
    dev/test/gen-scenarios.sh                # adds dev/test/scenarios/menu_mhi2_cpmap_diag
    dev/test/run.sh --record 'menu_mhi2_cpmap_diag' 'cpmap_diag_*'
    dev/test/run.sh 'menu_mhi2_cpmap_diag' 'cpmap_diag_*'      # expect: 2 passed
    dev/tools/lint.sh                    # expect: no new findings in cpmap_diag.sh (see note)
    dev/.tools/bin/shellcheck -s ksh mod/carplay_maps_vc/cpmap_diag_core.sh

Note on lint: on this branch `dev/tools/lint.sh` already reports 7 new findings before any change from this plan. All of them are in upstream V3.8.0 files (`esd/scripts/cpmap_status.sh`, `cpmap_install_790.sh`, `cpmap_install_791.sh`, `config/GLOBALS`), because the baseline was taken before the merge. Acceptance is that `esd/scripts/cpmap_diag.sh` adds none. `mod/carplay_maps_vc/` is not in `dev/tools/shell-sources.sh`, so the core script is checked separately and must be clean.

To re-run the analysis that led to this plan (optional):

    pip install --target dev/.tools/py capstone pyelftools numpy
    mkdir -p /tmp/cpjar && python3 -I -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        mod/carplay_maps_vc/payload/common/CarPlayClusterControls.jar /tmp/cpjar
    python3 -I dev/tools/re/jdis.py /tmp/cpjar/de/vw/mib/carplay/clustercontrol/*.class
    PYTHONPATH=dev/.tools/py python3 dev/tools/re/armdis.py mod/carplay_maps_vc/payload/profiles/MU1447/790/core.so \
        map_control_command_worker send_map_semantic_command log_path
    PYTHONPATH=dev/.tools/py python3 dev/tools/re/j9const.py <path to a backed-up MUxxxx-lsd.jxe> 'KEY_MFW_[A-Z0-9_]+|KBD_[A-Z0-9_]+'


## Validation and Acceptance

Milestone 1 is accepted when both scenarios pass and their `expected.stdout` shows the following. `menu_mhi2_cpmap_diag` prints "Status: not installed" and `CPMAP_DIAG_OK`. `cpmap_diag_mhi2_installed` prints the profile `MU1447/790`, one jar mention, the counts from its sample log, and the verdict about the key path. In both, `expected.files` shows new files only below `sd/backup/carplaymaps-diag/` and no change below `unit/`. `expected.journal` contains only the SD remount. Lint reports no new findings.

Milestone 2 (in the car, by the owner):

1. Copy the branch's SD content to the card (as for any M.I.B. release).
2. Connect the iPhone by cable, not through a wireless adapter. Start Apple Maps in CarPlay and switch the cluster to the map.
3. Press the steering-wheel "up" button briefly three times, then "down" three times. Then hold "up" for three seconds. Note what the cluster shows each time.
4. Without switching off, open the engineering menu: M.I.B. → CarPlay Maps VC → "Save CarPlay Maps VC diagnostics to SD". Read the verdict on screen. Copy `backup/carplaymaps-diag/<timestamp>/` from the card.

Accepted when the report exists and its verdict is recorded in `Surprises & Discoveries` with the event counts.


## Idempotence and Recovery

The diagnostics entry can run any number of times. Each run creates a new timestamped folder and changes nothing on the unit. If the SD card cannot be written, it prints `CPMAP_DIAG_FAIL=SD_NOT_WRITABLE` and stops. Scenario recording can be repeated. `gen-scenarios.sh` keeps existing goldens. The debug jar of Milestone 3 must be installed by its own entry that keeps the original jar, and the existing "Restore factory files" entry still restores the factory state completely.


## Artifacts and Notes

Steering-wheel constants in the owner's Seat `lsd.jxe` (DSIKeyPanel set):

    KBD_MFW = 4
    KEY_MFW_UP 38   KEY_MFW_DOWN 39          <- the only keys CarPlayClusterControls.jar accepts
    KEY_MFW_ARROW_A_UP 46   KEY_MFW_ARROW_A_DOWN 47
    KEY_MFW_ARROW_B_UP 48   KEY_MFW_ARROW_B_DOWN 49
    KEY_MFW_ARROW_RIGHT 36  KEY_MFW_ARROW_LEFT 37   KEY_MFW_ROLLER_LEFT 40  KEY_MFW_ROLLER_RIGHT 44
    KEY_MFW_MENU 35  KEY_MFW_CANCEL 41  KEY_MFW_VOLUME_UP 42  KEY_MFW_VOLUME_DOWN 43

Expected screen output of the diagnostics entry for the Seat symptom (from the golden of `cpmap_diag_mhi2_no_command`, shortened):

    lsd.jxe size: 55712574 (MU1447)
    == Installation
    Profile: MU1447/790
    dio_manager: CarPlay Maps VC wrapper
    lsd.sh mentions of the control jar: 1 (expected 1)
    == core.so events (carplaymaps-video.log)
    port 7032 ready/failed:  1/0
    zoom/map commands sent:  0
    == Verdict
    No steering-wheel command reached core.so. The jar only reacts to
    keyboard 4, keys 38/39 (KEY_MFW_UP/DOWN): this wheel sends other codes
    or the keys do not reach the head unit while the cluster shows the map.
    Saved to: backup/carplaymaps-diag/<timestamp>
    CPMAP_DIAG_OK

Key states used by the module (`Mhi2ClusterKeyState`): 0 released, 1 pressed, 3/4/5 long pressed. Zoom fires on "pressed". The map switch fires after 2,500 ms.


## Interfaces and Dependencies

`mod/carplay_maps_vc/cpmap_diag_core.sh <sd-root>`: exit 0 with last line `CPMAP_DIAG_OK`, or exit 1 with `CPMAP_DIAG_FAIL=<reason>` (`SD_NOT_FOUND`, `SD_NOT_WRITABLE`, `MMX_FILESYSTEM_NOT_FOUND`). It honours `CPMAP_TEST_ROOT` like the other cpmap scripts: if it is set, the unit's MMX file system and `/ramdisk` are taken from that directory, and no `mount` or `on` is run.

`esd/scripts/cpmap_diag.sh`: the menu wrapper; no arguments.

Analysis helpers in `dev/tools/re/` (developer PC only): `jdis.py` (Java class disassembler, no dependencies), `armdis.py` (ARM ELF function lister and disassembler, needs `capstone` and `pyelftools`), `j9const.py` (reads `static final int` constants from a J9 ROM image, needs `numpy`). Python packages go into `dev/.tools/py` (git-ignored) with `pip install --target`.


Revision note (2026-10-09 21:20Z): Milestone 1 implemented and tested in the simulator. Progress, Decision Log (scenario pruning, `pidin` stub, `$(...)` style), Outcomes, the lint note in Concrete Steps and the expected screen output in Artifacts were updated.
