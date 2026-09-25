# Refactor M.I.B. into a tested, library-based codebase without changing what it does to the car

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.agent/PLANS.md` (repository-relative path). Read that file before editing this plan. `.agent/AGENTS.md` requires an ExecPlan for significant refactors; this is that plan.


## Purpose / Big Picture

M.I.B. ("More Incredible Bash") is a collection of shell scripts that people copy onto an SD card and run on the infotainment head unit of Volkswagen-group cars (Harman MHI2, MHI2Q and MHIG units). It backs up the unit, patches its firmware so features such as CarPlay can be enabled, changes hidden settings, and adds a menu to the unit's hidden engineering screen. A mistake in these scripts can permanently disable ("brick") a unit that costs well over a thousand euros. Today nobody can change the code with confidence: there are no tests that run the real scripts, the same forty lines of setup are copied into 48 programs and 88 menu wrappers, and 434 places hard-code the SD card path.

After this plan is complete, a contributor can do three things they cannot do today. First, run `dev/test/run.sh` on an ordinary Linux laptop and see every M.I.B. function execute against a simulated head unit, with a pass/fail verdict that proves the refactored code still sends exactly the same commands to the unit as the original code did. Second, change shared behaviour such as logging, locking, or unit detection in one library file instead of in dozens of copies. Third, rely on a release process that refuses to package a build whose installer checksums are wrong, whose menu points at missing scripts, or whose flash code has not passed the flash test scenarios.

For the person in the car, nothing changes except where this plan deliberately fixes a defect, and every such fix is listed in the `Decision Log` with a test that shows the old and the new behaviour. The menu entries, the backup folder layout, the names of patch files, and the installation procedure all stay the same, so existing SD cards, existing backups and the existing wiki instructions remain valid.


## Progress

- [x] (2026-09-25 16:00Z) Read `.agent/AGENTS.md`, `.agent/PLANS.md`, `README.md`, `start`, all files in `config/`, `apps/flash`, `apps/launcher`, `apps/gem`, `apps/offset`, representative parts of `apps/backup`, representative `esd/scripts/*.sh`, the head of `esd/Launcher-sda0.esd`, `Launcher/*`, `metainfo2.txt`, and `tests/*`.
- [x] (2026-09-25 16:10Z) Compared `main` with `origin/beta`: `beta` branches from `main` at 2022-08-31, is 5 commits ahead and 452 commits behind. The beta-only content is catalogued under `Context and Orientation`.
- [x] (2026-09-25 16:20Z) Ran ShellCheck 0.10.0 over all shell sources as a baseline: 3,444 findings (4 parse errors, 240 warnings, 3,200 notes). The details are in `Surprises & Discoveries`.
- [x] (2026-09-25 16:30Z) Prototyped the head-unit simulator idea: an unprivileged Linux user and mount namespace can present the repository at `/net/mmx/fs/sda0` inside a `chroot` without changing any script. Evidence is in `Artifacts and Notes`.
- [x] (2026-09-25 16:40Z) Wrote this ExecPlan.
- [x] (2026-09-25 18:00Z) Milestone 0: local tags `baseline/pre-refactor` (`3f3caeb`) and `archive/beta-2022-11` (`144bf83`) exist, remote `upstream` was added and fetched (`main` equals `upstream/main`, 0/0), branch `refactor/core` was created, and `dev/NOTES-beta.md` was written. Both tags were pushed to origin (the Dizzard92 fork) on 2026-09-25 after the owner approved it and authenticated `gh`.
- [x] (2026-09-25 18:10Z) Milestone 1: `dev/README.md`, `dev/tools/install-deps.sh` (local install into `dev/.tools/`, no root), `dev/tools/shell-sources.sh` (150 files), `dev/tools/lint.sh` with the baseline `dev/lint/shellcheck-baseline.txt` (3,444 findings), `dev/tools/package.sh`, the `export-ignore` entries in `.gitattributes`, and `.gitignore` entries. Verified: lint exits 0 on the unchanged tree; an injected finding fails the run with "5 new"; the package has 292 files, no dev files, unchanged frozen checksums, CRLF for `metainfo2.txt` and the ESD files, LF for the apps.
- [x] (2026-09-25 18:30Z) Milestone 2 (prototyping, promoted): `dev/sim/mibsim`, `dev/sim/make-profile.py`, `dev/sim/lib/ifs.py`, stubs in `dev/sim/stubs/{boot,bin}`, and four profiles (`mhi2`, `mhig`, `mhig-scan-ba0000`, `mhig-scan-be0000`). Promotion criterion met: every profile runs `backup -a`, `offset -log`, `vim -s 0 c7`, `svm -f`, `flash -p`, and `flash -r` with exit 0 and empty stderr, 24 runs in 102 s. With a prepared patch folder, MHI2 `flash -p` journals `flashit -a ba0000` and leaves the patched image byte-identical in the simulated flash at `0xba0000`.
- [ ] Milestone 3: characterization ("golden master") tests for every menu entry and every `start` option.
- [ ] Milestone 4: shared library `lib/` (environment, logging, locking, unit identity, UI, help text), plus compatibility shims in `config/`.
- [ ] Milestone 5a: migrate read-only and informational apps to `lib/`.
- [ ] Milestone 5b: migrate apps that write settings (EEPROM and persistence writers).
- [ ] Milestone 5c: migrate the critical path apps: `backup`, `offset`, `flash`, `fecel`, `addfec`, `rccd`, `reboot`, `launcher`, `gem`.
- [ ] Milestone 6: generate `esd/scripts/*.sh` from one manifest, and add the menu consistency checks.
- [ ] Milestone 7: deliberate safety fixes, each with a failing test first.
- [ ] Milestone 8: continuous integration and the release packaging check.
- [ ] Milestone 9: validation on a real bench unit and a community pre-release.


## Surprises & Discoveries

- Observation: the `beta` branch is not an in-progress successor of `main`. It is a stale 2022 experiment. Its "live patch" flash code was committed with the note "Flash script still in debug mode. No flash will be conducted." `main` has since shipped a different live-patch implementation for MHIG units: `DB_PARSER` together with `apps/sbin/patcher` and `mod/patch_pattern/*.pattern` in `apps/flash`.
  Evidence: `git rev-list --count main..origin/beta` prints 5 and `git rev-list --count origin/beta..main` prints 452. The commit message of `279943d` reads "Live PATCH BETA ... Flash script still in debug mode."

- Observation: three files are pinned by SHA-1 checksums that the head unit's software-download process verifies. Changing a single byte of `Launcher/final/finalScript.sh` or `Launcher/version/MIB` breaks installation for every user.
  Evidence: `sha1sum Launcher/final/finalScript.sh` prints `ba391875e14a8794b683cc02556990fcb555fe08`, which equals `FinalScriptChecksum` in `metainfo2.txt` and `CheckSum` in `Launcher/final/hashes.txt`. `Launcher/version/MIB` hashes to `dd0d39ca…`, which equals the `CheckSum` in `metainfo2.txt`.

- Observation: `apps/gem -i` (reached from `start` option G) always links the MHI2 menu file, even on MHIG units. `apps/launcher -all` correctly chooses `Launcher-MHIG-sda0.esd` on MHIG units.
  Evidence: `apps/gem` line 35 hard-codes `Launcher-sda0.esd`, while `apps/launcher` lines 97 to 103 test `*MHIG*`.

- Observation: the engineering-menu files reference three scripts that do not exist, one of them in a real menu entry (`backupplus_speech.sh`). Seven scripts in `esd/scripts/` are not referenced by any menu file.
  Evidence: the orphan scan in `Artifacts and Notes` lists `esd/scripts/backupplus_speech.sh`, `XXXX.sh`, and `xxx.sh` as missing, and lists `b2nand.sh`, `backup.sh`, `bfecel.sh`, `conversion_fix_eu.sh`, `patch.sh`, `settrain.sh`, and `showimage_test.sh` as unreferenced.

- Observation: the version shown in the menu has drifted from the `VERSION` file, and both menu files claim to be the "MHIG Edition".
  Evidence: `VERSION` contains `V3.7.3 "long time ago..."`, while both `esd/*.esd` files carry the label `M.I.B. - More Incredible Bash - V3.7.2 MHIG Edition`.

- Observation: flash success is judged by a weak heuristic. After writing, `apps/flash` compares the string lengths of the "programming" and "erasing" lines in the flash tool's log. It never reads the written region back to compare it with the image. The code itself carries a TODO that says so.
  Evidence: `apps/flash` lines 84 to 92 and the TODO on line 337.

- Observation: `apps/flash -r` (restore the original firmware part from backup) flashes the backup file as soon as it exists. It does not check its size, header, or checksum. `apps/backup` treats any existing backup file as complete ("Backup is already there!"). A backup that was cut short by power loss would therefore later be flashed as the "original".
  Evidence: `apps/flash` lines 352 to 368, and the repeated `if [ ! -f $BACKUPFOLDER/... ]` pattern in `apps/backup`.

- Observation: apps call each other by sourcing them with `. $thisdir/<app> <args>` instead of executing them. Inside a sourced app, `$0`, and therefore `thisname`, is the caller's name. An `exit` inside the sourced app terminates the caller. Variables such as `OFFSETPART2` and `STAGE2SIZE` flow back to the caller through this mechanism. That is a hidden interface.
  Evidence: `apps/flash` sources `backup -a`, `offset -log`, `rccd -d`, `fecel -fec`, `fecel -el`, `showimage`, and `reboot -t 10`. `apps/backup` sources `pers` and `eeprom2bin`. `apps/fecel` sources `addfec`. There are 13 such app-to-app source lines in total.

- Observation: the existing `tests/` folder does not test the product code. It writes small throw-away scripts that imitate the locking pattern and tests those, and it checks the real files only with `bash -n`. The real target shell is not bash.
  Evidence: `tests/test_lock_files.sh`, functions `test_lock_creation` through `test_cleanup_sigint`.

- Observation: ShellCheck baseline with `-s ksh`: 2,655 × SC2086 (unquoted variable), 199 × SC2317 (unreachable code, mostly help blocks after `return`), 137 × SC2027 (quote juggling), 65 × SC2034 (unused variables), and 4 parse errors in `apps/vim` line 42 and `apps/subwoofer` line 28. Those two lines, `[ ! -z $VIM 2>/dev/null ]`, are valid shell. ShellCheck simply cannot parse a redirection inside `[`.
  Evidence: the output of the ShellCheck command in `Concrete Steps`, Milestone 1.

- Observation: every binary in `apps/sbin/` is a 32-bit ARM QNX executable. None of them can run on a development PC. `apps/sbin/beta/` holds newer, statically linked builds plus `micropython`, which only the experimental `apps/beta` script uses.
  Evidence: `file apps/sbin/*` reports "ELF 32-bit LSB executable, ARM, EABI5 ... interpreter /usr/lib/ldqnx.so".

- Observation: the development machine has no password-less `sudo`, so `apt-get install` is not available to an agent. `apt-get download` plus `dpkg-deb -x` works without root, and so does a checksum-pinned ShellCheck release tarball. `install-deps.sh` therefore installs into `dev/.tools/` instead of the system.
  Evidence: `sudo -n true` prints "sudo: a password is required". `dev/tools/install-deps.sh` prints mksh R59, shellcheck 0.10.0, bc 1.07.1, and xxd 2021-10-22.

- Observation: `export-ignore` also affects the "Download ZIP" button on GitHub, which uses `git archive`. That is how most users get M.I.B. Since Milestone 1, those downloads no longer contain `tests/`, `.agent/`, or `.github/`. This is intended, and nothing on the unit referenced them.
  Evidence: `grep -rn "tests/\|\.agent\|\.github" apps config esd start Launcher` finds nothing.

- Observation: `.agent/AGENTS.md` and `.agent/PLANS.md` exist only in the working copy (untracked). This plan, `.agent/execplans/mib-refactor.md`, is committed. A future contributor who clones the repository gets the plan but not `PLANS.md` unless the owner commits it.
  Evidence: `git status --short` shows `?? .agent/AGENTS.md` and `?? .agent/PLANS.md`. Resolved on 2026-09-25: the owner approved it, and both files were committed in `8076b25`.

- Observation: this environment cannot push to GitHub. There is no `gh` CLI and no HTTPS credential helper, and GitHub rejects the SSH key (`Permission denied (publickey)`). The owner approved pushing the tags to the fork `https://github.com/Dizzard92/M.I.B._More-Incredible-Bash.git`, but the push has to be run by the owner.
  Evidence: `git push https://github.com/Dizzard92/... refs/tags/...` prints "fatal: could not read Username for 'https://github.com'". Resolved on 2026-09-25: the owner ran `gh auth login` (the git credential helper is now `gh auth git-credential`), and the tags were pushed. `git ls-remote --tags origin` lists `archive/beta-2022-11` (`144bf83`) and `baseline/pre-refactor` (`3f3caeb`).

- Observation: in bash with `set -o pipefail`, `producer | grep -q` can fail when `grep` exits early and the producer (here `python3 -m zipfile -l`) gets SIGPIPE. `package.sh` therefore reads the zip listing once into a variable.
  Evidence: the first run printed "error: VERSION missing from package" and a Python `BrokenPipeError`, although `VERSION` was in the zip.

- Observation: the bundled tools on the unit do not handle hexadecimal case consistently, and this breaks offset arithmetic. `apps/sbin/xxd` is "xxd V1.10 27oct98" and prints offsets with `%08lx`, i.e. lower case, even with `-u`. `apps/sbin/bc` is GNU bc from the QNX 6.5 SDK (copyright up to 2000). With `ibase=16` it reads lower-case letters as variable names, so `ba0000` evaluates to 0. Three defects follow, all reproduced in the simulator with the host's xxd and GNU bc, which behave the same way:
  1. On a unit without `/net/rcc/usr/bin/flashlock`, `apps/offset -log` finds the image with `xxd | grep`. It then feeds the lower-case relative offset to `bc`. For stage-2 offsets whose relative value contains a letter (`be0000`, `c00000`, `c20000`; not `ba0000` or `bc0000`), the result is 0, so OFFSETPART2 becomes `540000` and STAGE2SIZE becomes `00000000`. `apps/backup -a` stores these wrong values in `<MU>-ifs-root-part2-OFFSET.txt`, and saves a 24 MiB "stage-2 backup" taken from the wrong place.
  2. On the same scan path, a correct result is printed by `bc` in upper case (`BA0000`), while `patches/MHIG_patch_db.csv` stores `ba0000`. `apps/flash -p` compares them case-sensitively and stops with "OFFSETPART2 in DB and RCC flash do NOT match".
  3. With `flashlock` present, the offset is lower case (`ba0000`), so the DB comparison passes. But `DDCALC` in `apps/flash` gives it to `bc`, which yields 0, so the "dump" of stage 2 is read from flash offset 0, and the SHA-1 check stops with "sha1 ... is NOT found in DB".
  In every case the MHIG live patch stops before `flashit`, so it fails safely. Whether real MHIG units print upper- or lower-case offsets in `flashlock` must be confirmed from a real MHIG log. Defect 3 assumes lower case.
  Evidence: `strings apps/sbin/xxd` shows `%08lx:` and `xxd V1.10 27oct98`; `echo "ibase=16; ba0000" | bc` prints `0`; simulator runs `check-mhig-scan-be0000-offset_-log` ("offset: 0x00540000"), `check-mhig-scan-ba0000-flash_-p` ("do NOT match"), and `check-mhig-flash_-p` (DEBUG block in the log: `SHA1_PATCH` differs from `SHA1_FEC_CP`, and the dumped `_check.ifs` is all zero bytes).

- Observation: the offset allow-list in `IFSstage2` in `apps/flash` (`ba0000`, `bc0000`, `be0000`, `c00000`, `c20000`, either case) is the last barrier against defect 1 above. After `backup -a` stored offset `540000`, `flash -r` builds `...-ifs-root-part2-0x00540000.ifs` and refuses with "Flash offset unknown, flashing aborted!". Without that list it would write a 24 MiB image to the wrong flash address. The refactor must keep this list or replace it with something at least as strict.
  Evidence: simulator run `check-be0000-backup-then-restore` (`backup -a` followed by `flash -r` on profile `mhig-scan-be0000`). The journal contains no `flashit` line.

- Observation: `apps/svm -f` needs `/net/rcc/mnt/efs-persist/SWDL/Log/CfgAckRand.z` on the unit. When the file is missing, `apps/zlib` prints its help text, which starts "Usage: svm". That is visible proof that a sourced app inherits `$0` from its caller. The SVM run then continues. With the file present (the simulator creates a zlib stream of `svm_rand`), the full path runs: `modifyE2P w 3f0 00 00 01`, then a reboot.
  Evidence: the first `svm -f` simulator run printed "zlib v0.1.3 ... Usage: svm [OPTION]"; the rerun journals `modifyE2P w 3f0 00 00 01` and `mib2_ioc_flash reboot`.

- Observation: `apps/backup` computes free space as `df -k /net/mmx/mnt/boardbook | awk '{print $4}'` and uses the result in `[[ $SIZE -gt 5000 ]]`. That only works if QNX `df` prints no header line, so the `df` stub prints none. With the host's `df`, the header word "Available" ended up in the arithmetic and mksh reported "unexpected".
  Evidence: stderr of the first `backup -a` simulator run: `apps/backup[569]: Available 985628112: unexpected`.

- Observation: overlayfs cannot be mounted inside an unprivileged user namespace on this WSL2 kernel, not even with `userxattr`. The simulator therefore builds `/usr` as a tmpfs of symbolic links into a bind mount of the host's `/usr` at `/.host/usr`. That lets it add `/usr/apps/modifyE2P`, `/usr/apps/MIBRoot`, and `/usr/bin/flashlock`, which scripts reach through `on -f rcc`.
  Evidence: `mount -t overlay ... -o userxattr,lowerdir=/usr,...` prints "wrong fs type, bad option".

- Observation: repository files are mode 644, and the unit ignores permissions (FAT32). The simulator marks every file of the SD copy executable, otherwise even `apps/offset` fails with "Permission denied" (exit 126).
  Evidence: the first `mibsim` run: `apps/offset: can't execute: Permission denied`.

- Observation: the head-unit paths can be simulated on Linux without root and without editing any script, using `unshare --user --map-root-user --mount` plus `chroot`. This is the foundation for Milestones 2 and 3.
  Evidence: see "Simulator feasibility prototype" in `Artifacts and Notes`.


## Decision Log

- Decision: refactor in place, in shell (Korn-shell dialect), and do not rewrite in another language.
  Rationale: the only interpreter that is guaranteed to exist on every supported unit is the QNX system shell (`/bin/sh`, a Korn-shell derivative; `Launcher/final/finalScript.sh` explicitly uses `/bin/ksh`). `apps/sbin/beta/micropython` has never been validated on units and would add a 870 KB binary dependency to a flashing tool. Keeping the language keeps every contributor and every wiki page relevant.
  Date/Author: 2026-09-25, Claude (planning session for Marco Nacken).

- Decision: behaviour-preserving refactoring comes first, and it is proven by characterization tests that compare the sequence of commands sent to the (simulated) unit. Deliberate behaviour changes (bug fixes) happen only in Milestone 7, one at a time, each with its own test and its own entry in this log.
  Rationale: in an automotive flashing tool the dangerous regressions are "a different command was sent" or "a command was sent in a different order", not "the text looks different". Mixing clean-up and fixes in one change makes both unreviewable.
  Date/Author: 2026-09-25, Claude.

- Decision: `main` is the only base for the refactor. `beta` is not merged. It is preserved as the tag `archive/beta-2022-11` and otherwise left untouched. Nothing from `beta` is ported during this plan. The one open item from `beta` ("Korea" as `region7` in `metainfo2.txt`, replacing a duplicate `RoW`) is recorded as a candidate for a separate, hardware-validated change, because `metainfo2.txt` is read by the unit's installer and this plan freezes it.
  Rationale: `beta`'s flash changes were explicitly non-functional ("debug mode"). Its `modelconversion` and `unit_db` design was superseded on `main` by `patches/MHIG_patch_db.csv` and `DB_PARSER`. `ascii2hex` duplicates `hex2ascii` plus `xxd`. Its deletions (tests, ssh daemon, images) would be regressions.
  Date/Author: 2026-09-25, Claude.

- Decision: deleting or force-pushing any remote branch (including `origin/beta`) is out of scope for autonomous execution. The implementer creates the archive tag locally and pushes it only if the repository owner has approved pushing.
  Rationale: remote branch deletion is outward-facing and hard to reverse. Other people track this fork and its upstream.
  Date/Author: 2026-09-25, Claude.

- Decision: the following interfaces are frozen for the whole plan. The byte content of `metainfo2.txt`, `Launcher/final/finalScript.sh`, `Launcher/final/hashes.txt`, and `Launcher/version/MIB`. The paths `esd/Launcher-sda0.esd` and `esd/Launcher-MHIG-sda0.esd`. Every path `/net/mmx/fs/sda0/esd/scripts/<name>.sh` that a menu file references. The command-line options of every file in `apps/`. The lock-file names `/net/rcc/dev/shmem/<name>.mib`, which must remain regular files. The backup folder name `backup/<MU>-<TRAIN>-<FAZIT>/` and every file name inside it. The patch folder and file naming under `patches/`.
  Rationale: units in the field hold a symbolic link to the menu file on the SD card, users hold years of backups, and the wiki documents the options. Any change there strands users.
  Date/Author: 2026-09-25, Claude.

- Decision: binaries in `apps/sbin/`, `apps/sbin/beta/`, `mod/sshd/`, `mod/gem/`, and `mod/java/` are not rebuilt, replaced, or removed. They get a checksum manifest so accidental modification is detected.
  Rationale: their provenance and build recipes are not in the repository. Swapping a binary is a behaviour change that can only be validated on hardware.
  Date/Author: 2026-09-25, Claude.

- Decision: developer-only material lives in a new top-level `dev/` folder and is excluded from the user package through `export-ignore` in `.gitattributes`. The folders `tests/`, `.agent/`, and `.github/` are excluded the same way.
  Rationale: users "extract all files to the root of the SD card". Tooling must not end up on the card or confuse users.
  Date/Author: 2026-09-25, Claude.

- Decision: the menu wrapper scripts in `esd/scripts/` stay as individual files at their current paths, but are generated from one manifest instead of being hand-copied.
  Rationale: it is not verified whether the engineering-menu `script` entry can pass arguments to a script, so a single generic runner is not safe. Generated files keep the field-facing paths identical while removing the duplication for maintainers.
  Date/Author: 2026-09-25, Claude.

- Decision: the reference shell for all host-side checks is `mksh`. Code must stay inside the feature set that both `mksh` and the QNX Korn shell accept. Allowed: `[[ ]]`, `$(( ))`, `${#v}`, `${v%pat}`, `${v#pat}`, indexed arrays, the `function name {` syntax, `typeset`, and `set -o noclobber`. Not allowed: `local`, `declare`, `mapfile`, `${v,,}`, `${v^^}`, `<<<`, process substitution, and `[[ =~ ]]`.
  Rationale: `mksh` is the closest living descendant of the public-domain Korn shell that QNX ships. Bash accepts far more than the unit does, so `bash -n` (used by the current `tests/`) gives false confidence. No existing script uses `local` (verified with grep), so the rule costs nothing.
  Date/Author: 2026-09-25, Claude.

- Decision: developer tools are installed per checkout into `dev/.tools/` (git-ignored) by `dev/tools/install-deps.sh`, and the dev scripts prepend `dev/.tools/bin` to `PATH`. A system-wide `apt-get install` is not required. The ShellCheck version is pinned (0.10.0) and its tarball is verified with SHA-256.
  Rationale: agents and contributors cannot rely on root access (see `Surprises & Discoveries`). A pinned version keeps the ratchet baseline stable, because different ShellCheck versions report different findings.
  Date/Author: 2026-09-25, Claude.

- Decision: `Launcher/final/finalScript.sh` is included in lint (read-only). ShellCheck findings in it are accepted permanently, because the file is frozen.
  Rationale: syntax problems there would break installation, so checking it costs nothing. It can never be edited.
  Date/Author: 2026-09-25, Claude.

- Decision: `mibsim` takes the SD content from the working tree by default (tracked and untracked, not ignored, minus `dev/`, `tests/`, `.agent/`, `.github/`, and `dist/`). `--rev <commit>` takes it from a commit. This replaces the earlier plan text, which defaulted to `git archive HEAD`.
  Rationale: during a refactor, the tests must see uncommitted edits. Recording goldens on the baseline uses `--rev baseline/pre-refactor`, so nothing is lost.
  Date/Author: 2026-09-25, Claude.

- Decision: the simulator provides four profiles instead of two. `mhi2` and `mhig` have the `flashlock` tool. `mhig-scan-ba0000` and `mhig-scan-be0000` lack it and exercise the flash scan in `apps/offset`. The MHIG profiles use a fictional firmware `9999`; `mibsim` appends its row to `patches/MHIG_patch_db.csv` in the simulated SD copy only.
  Rationale: the two offset code paths have different defects (see `Surprises & Discoveries`), and the characterization tests must pin both. Real MHIG checksums cannot be reproduced without the proprietary images, so a synthetic firmware with self-consistent checksums is the only way to reach the flash steps.
  Date/Author: 2026-09-25, Claude.

- Decision: unit-tool output formats that the repository does not show are inferred from the parsers that consume them, and marked as assumptions in the stub source. That covers the `modifyE2P` hex lines, the `flashlock` table, the `flashit` erase/program lines, `updatePersistence` read output, and `df` without a header. They must be checked against a real unit log before Milestone 9.
  Rationale: the characterization tests pin the commands M.I.B. sends, and those do not depend on these formats. Only the code path taken does, and each path is visible in the golden output.
  Date/Author: 2026-09-25, Claude.

- Decision: the offset case defects and the scan defect are recorded now but fixed only in Milestone 7, together with the existing "normalize the flash offset" item.
  Rationale: Milestones 3 to 6 must reproduce today's behaviour exactly, including failures that are safe today.
  Date/Author: 2026-09-25, Claude.

- Decision: plan documents are written in English.
  Rationale: `.agent/PLANS.md`, the code comments, the README, and the international contributor base are English.
  Date/Author: 2026-09-25, Claude.


## Outcomes & Retrospective

Milestone 2 is complete (2026-09-25). The simulator reaches every critical code path: backup, offset detection by both methods, the MHI2 flash with validation, the MHIG live-patch checks, SVM, VIM, and reboot. It already found three latent defects in MHIG offset handling (see `Surprises & Discoveries`). They all fail safely today, but together they mean the MHIG live patch probably never reaches the flash step. That needs confirmation from a real MHIG log. A full run of the 24 checks takes about 100 seconds. Next is Milestone 3, the characterization scenarios.

Milestones 0 and 1 are complete (2026-09-25). The tree can now be linted (`dev/tools/lint.sh`, 150 files, 0 syntax errors, ShellCheck ratchet at 3,444) and packaged (`dev/tools/package.sh`) reproducibly without root. No head-unit code was changed. Next is Milestone 2, the simulator.

Planning complete (2026-09-25). The main risk identified is that the refactor could silently change which commands reach the unit. The characterization harness (Milestones 2 and 3) is the mitigation and must be finished before any production file is edited. Update this section at the end of every milestone.


## Context and Orientation

This section explains everything a newcomer needs. The terms below are used throughout the plan.

A "head unit" is the infotainment computer in the dashboard. M.I.B. supports three generations. "MHI2" (also called MIB2 High, made by Harman) and its successor "MHI2Q" are identified in this code as model 1 (current firmware) or model 2 (very old firmware). "MHIG" (MIB1 High) is model 3. The variable `MIBMO`, set in `config/GLOBALS`, holds that number. An app declares the highest model it supports in `MIBCAP` and then sources `config/MIBCHECK`, which aborts the app if the unit's model number is larger.

The unit runs QNX, a real-time operating system, on two processors that are networked together. "RCC" is the processor that owns the flash memory, the EEPROM, and the boot images. "MMX" runs the user interface and mounts the SD card. From MMX, the RCC's file system is visible under `/net/rcc/...`, and MMX's own file system is visible under `/net/mmx/...`. The QNX command `on -f rcc <command>` runs a command on the RCC. The SD card in slot 1 appears as `/net/mmx/fs/sda0`. `config/USB` also knows slot 2 (`sdb0`) and USB (`usb0_0`), but most code hard-codes `sda0`.

The "GEM" (Green Engineering Menu) is a hidden service screen on the unit. Its screens are defined in text files called "ESD files" (engineering screen definitions). M.I.B. ships two, `esd/Launcher-sda0.esd` for MHI2 and `esd/Launcher-MHIG-sda0.esd` for MHIG. They are about 4,000 lines each and have CRLF line endings, as required by `.gitattributes`. Installation places a symbolic link `/net/mmx/mnt/app/eso/hmi/engdefs/z_Launcher-sda0.esd` on the unit that points to the ESD file on the SD card. Each menu entry of type `script` names an absolute path such as `/net/mmx/fs/sda0/esd/scripts/svm.sh`. Those 88 wrapper scripts set `PATH`, set `GEM=1` (which tells apps to suppress colours and interactive prompts), print a warning banner, optionally refuse to start if a lock file exists, and call one or more programs in `apps/`.

"SWDL" (software download) is the unit's firmware-update mechanism. M.I.B. is installed by starting a software update from the SD card. The unit reads `metainfo2.txt` and runs `Launcher/final/finalScript.sh`, whose SHA-1 checksum is written into `metainfo2.txt`. The final script runs `Launcher/stuff.sh`, which is not checksummed and can be changed freely. `stuff.sh` runs `apps/backup -b` and `apps/launcher -all`, which installs the menu link and turns on the engineering menu. `_Swdlautorun.txt` and `Swdlautorun.txt` control automatic starting of that process.

The interactive alternative is `start` in the repository root. It is a numbered text menu for people who log into the unit over a serial or network console.

"IFS" (image file system) is QNX's boot image format. "ifs-root-stage2" is the second-stage root image in RCC flash. The central M.I.B. feature, "patching", replaces that image with a modified one that accepts additional feature codes. `apps/offset -log` finds where the image sits in flash (`OFFSETPART2`, a hex offset) and how big it is (`STAGE2SIZE`, a little-endian hex header value). `apps/flash -p` verifies the preconditions and writes the image with `apps/sbin/flashit`. `apps/flash -r` writes back the image saved by `apps/backup`. For MHI2 units the patched image comes from a pre-made folder `patches/<TRAIN>_<MU>_PATCH/`. For MHIG units it is generated on the unit by `apps/sbin/patcher` from the dumped image and verified against `patches/MHIG_patch_db.csv`.

A "FEC" (feature enabling code) unlocks a feature. They live in `/net/rcc/mnt/efs-persist/FEC/FecContainer.fec`. `apps/addfec` and `apps/fecel` add the codes listed in `patches/addFec/**/addFecs.txt`. The "EL" (exception list) is an older alternative mechanism stored under `patches/EL/`.

The "EEPROM" is a small non-volatile memory holding identity data. It is read with `on -f rcc /net/rcc/usr/apps/modifyE2P r <hexaddr> <hexlen>`. The following is read from it, with the same long `sed | xxd` pipeline copied more than ten times across `config/`: "Train" (`TRAINVERSION`, a firmware family name such as `MHI2_ER_SKG13_P4526`), "MU" (`MUVERSION`, the firmware release number, e.g. `MU1440`), "FAZIT" (a unique unit serial), part number, coding, and more. "Persistence" is a key/value store for settings, read and written with `apps/sbin/pc`, `apps/sbin/dumb_persistence_reader`, `/net/mmx/eso/bin/dumb_persistence_writer`, and `apps/sbin/updatePersistence`. Examples of settings apps are `apps/vim` (video-in-motion speed limit), `apps/svm` (clears a component-protection error), and `apps/carp` (CarPlay).

A "lock file" is an empty file `/net/rcc/dev/shmem/<name>.mib` (`TMP` in `config/GLOBALS`). Long operations create it so that a second tap on a menu entry does not start a second flash or backup in parallel. Menu wrappers test for `backup.mib`, `flash.mib`, and `reboot.mib` with `[ -f ... ]`, so lock files must remain regular files.

Backups are written to `backup/<MU>-<TRAIN>-<FAZIT>/` on the SD card. The log file there, `<MU>-LOG.txt`, is created by `config/LOGS` and appended to by every app. Its first lines contain the unit's VIN (vehicle identification number). Real logs and backups are therefore personal data and must never be committed.

How configuration is loaded today: an app sets `thisname` and `thisdir` from `$0`. If `LOG` is empty, it sources `config/GLOBALS`. That file sources `apps/mounts -usb` (which remounts USB storage), write-tests the SD card, defines absolute paths to the tools in `apps/sbin/`, reads identity from the EEPROM, sets `MIBMO`, and sources `config/LOGS`. `config/LOGS` creates the log header and defines the function `ERROR`, which, despite its name, prints " -> done :-)" or " -> failed!" based on the previous command's exit status. `config/BASICS` is a lighter version that `Launcher/stuff.sh` and `esd/scripts/patch_aio.sh` use. `config/LOCALS` reads additional identity values.

Apps also call each other by sourcing, for example `. $thisdir/backup -a` inside `apps/flash`. In that case, `$0` and `thisname` are the caller's, `exit` ends the caller too, and variables flow back to the caller. Milestone 3 documents every such edge, and Milestone 5 preserves them.

The `beta` branch. `origin/beta` forked from `main` on 2022-08-31. Its five own commits (`de1328b` "unit DB", `933056a` "model conversion tool", `b1f637b` "Flash live patch", `279943d` "Live PATCH BETA", `144bf83` "added Korea region") add `apps/modelconversion`, `mod/unit_db/unit_db` (five MHI2 firmware rows with header sizes and SHA-1 values), `apps/ascii2hex`, `apps/rdiff`, a non-functional live-patch path in `apps/flash`, and a `metainfo2.txt` change (`region7 = "Korea"`, with "FREE for all" removed from the display names). Compared with today's `main`, it lacks everything since 2022: `tests/`, `mod/sshd`, `mod/tmc`, most images, `patches/EL`, `patches/MHIG_patch_db.csv`, and dozens of apps. One useful thing to keep from `beta` for later reference is the idea of a table of known stock and patched checksums per firmware, which `main` already implements for MHIG in `patches/MHIG_patch_db.csv`.

The repository is a fork: `origin` is `https://github.com/Dizzard92/M.I.B._More-Incredible-Bash.git`. Upstream is `https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash` (named in `README.md`), which keeps merging community pull requests (the latest merge on `main` is `#964`, 2026-09-23). A large refactor will conflict with those. The plan therefore lands in small milestone-sized commits and syncs with upstream before every milestone.

Size of the code base at planning time: 48 app scripts (8,438 lines), 88 menu wrappers (2,936 lines), two ESD files (7,519 lines), 8 config fragments, and 299 files in total.


## Plan of Work

The work runs in ten milestones. Milestones 0 through 3 build the safety net and must be finished before any production file is edited. Milestones 4 and 5 do the refactor under that net. Milestone 6 removes the wrapper duplication. Milestone 7 fixes defects deliberately. Milestones 8 and 9 make the result releasable.

### Milestone 0: baseline and branch hygiene

Scope: freeze a reference point, isolate the work, and deal with `beta` without destroying anything. At the end, the tag `baseline/pre-refactor` points at the current `main` commit `3f3caeb`. The tag `archive/beta-2022-11` points at `origin/beta` (`144bf83`). A work branch `refactor/core` exists, and a remote named `upstream` points at the Mr-MIBonk repository. Create a file `dev/NOTES-beta.md` that records the beta analysis from `Context and Orientation`, so the knowledge survives even if the branch is deleted later. Acceptance: `git tag -l 'baseline/*' 'archive/*'` lists both tags, and `git log -1 --format=%h baseline/pre-refactor` prints `3f3caeb`.

### Milestone 1: tooling, the `dev/` folder, packaging exclusions, and a ShellCheck ratchet

Scope: make the development tools reproducible and keep them out of the user package. Create `dev/README.md`, which explains the folder in plain words. Create `dev/tools/install-deps.sh`, which installs `mksh`, `shellcheck`, `bc`, `xxd`, and `python3` with `apt-get` on Debian or Ubuntu and prints versions. Create `dev/tools/lint.sh`, which runs `mksh -n` over every shell source and runs ShellCheck with `-s ksh -f gcc`. The list of shell sources is `start`, every regular file directly in `apps/`, `config/BASICS`, `config/GLOBALS`, `config/LOCALS`, `config/LOGS`, `config/MIBCHECK`, `config/USB`, `esd/scripts/*.sh`, `Launcher/stuff.sh`, `mod/custom.sh`, `mod/sshd/scripts/*.sh`, and later `lib/*.sh`.

The ShellCheck output is compared against the committed baseline `dev/lint/shellcheck-baseline.txt`, with line numbers stripped so that moving code does not count as new findings. The comparison uses the file name, the code, and the message text. The script fails only if a finding appears that is not in the baseline, and it prints the count of findings that disappeared. That is the "ratchet": the number can only go down.

Add these lines to `.gitattributes` so that `git archive` produces the SD-card package without developer material: `/dev export-ignore`, `/tests export-ignore`, `/.agent export-ignore`, `/.github export-ignore`. Add `dev/tools/package.sh`, which runs `git archive --format=zip -o dist/MIB-<version>.zip HEAD`, where `<version>` is the first word of `VERSION`. Add `dist/` to `.gitignore`.

Acceptance: `dev/tools/lint.sh` exits 0 on the unchanged code base. `unzip -l dist/MIB-V3.7.3.zip` lists `start`, `metainfo2.txt`, `apps/flash`, and `esd/Launcher-sda0.esd`, and lists nothing under `dev/`, `tests/`, or `.agent/`.

### Milestone 2 (prototyping): head-unit simulator

Scope: a host program that runs any M.I.B. script exactly as the unit would, but against fake hardware, and records every command that would touch the unit. At the end, `dev/sim/mibsim --profile mhi2 -- /net/mmx/fs/sda0/apps/vim -s 0 c7` runs and leaves a journal, a log, and captured output in a result folder. This is labelled prototyping because the fidelity of the stubs is the main technical unknown. The promotion criterion is at the end of this milestone.

How it works. `dev/sim/mibsim` is a bash script that runs on the host. It creates a result folder, by default `dev/sim/out/<timestamp>/`, holding a copy of the SD card, a fake root file system, and the outputs. By default, the SD copy is the working tree: files listed by `git ls-files -co --exclude-standard`, minus `dev/`, `tests/`, `.agent/`, `.github/`, and `dist/`. With `--rev <commit>`, it is `git archive <commit>`. Every file in the copy is made executable, as on FAT32. Scripts write backups and logs to the card, so the real checkout must never be mounted.

It then re-executes itself inside `unshare --user --map-root-user --mount --fork`. Inside, it mounts a `tmpfs` as the new root. It bind-mounts the host's `/usr` at `/.host/usr` and builds `/usr` as a `tmpfs` of symbolic links into it: one link per entry of `/usr/bin`, and one per other child of `/usr`. It recreates `/bin`, `/lib`, and similar paths as the same symbolic links as on the host (merged `/usr`), or bind-mounts them if they are real directories. It bind-mounts `/etc`. The tmpfs approach replaced an overlayfs attempt that the WSL2 kernel refused (see `Surprises & Discoveries`). It binds `/dev` and the SD copy to `/net/mmx/fs/sda0`, builds the fake unit tree described below, and runs the command through `chroot` with `/usr/bin/sh` and `/usr/bin/ksh` pointing at a copy of `mksh` in `/opt/sim/bin`. `bc` is copied there too, because it is usually missing on hosts. `awk` points at `gawk`, because `apps/eeprom2bin` uses `strtonum`.

Stub placement follows the unit's own layout. Every M.I.B. script puts `/proc/boot` first in `PATH`, and QNX keeps its boot-image tools there. The simulator does not mount `procfs`. It creates `/proc/boot` as a plain directory in the fake root and places the stubs there, so they shadow host tools such as `mount` without editing any script.

The stubs for unit tools live in `/sim/stubs` (source: `dev/sim/stubs/bin/`), and the QNX system commands live in `/proc/boot` (source: `dev/sim/stubs/boot/`: `on`, `mount`, `umount`, `sleep`, `sync`, `top`, `slay`, `use`, `df`). Every stub that changes the unit appends one line to `/sim/journal` in the form `<stub-name>\t<arg1>\t<arg2>...`. It reads its behaviour from `/sim/profile/`. The stubs are:

- `on`: drops `-f <node>` and executes the remaining arguments.
- `mount`: journals and returns 0.
- `top`: prints a memory line with 300M available, or the value in `/sim/profile/free_ram_mb`.
- `sleep`: journals and returns immediately, so tests are fast.
- `/net/rcc/usr/apps/modifyE2P`: for `r <addr> <len>`, prints the bytes from `/sim/profile/eeprom.bin` in the text format described in `Interfaces and Dependencies`. For `w`, it journals and patches the file.
- `/net/rcc/usr/apps/mib2_ioc_flash`: journals only. This is the reboot path.
- `/net/rcc/usr/bin/date`: prints the fixed time `2026_01_01_00_00_00` so logs are reproducible.
- `/net/rcc/usr/bin/sha1sum`: calls the host `sha1sum`.
- `/net/rcc/usr/bin/flashlock` (present only if the profile has `flashlock.txt`): prints that file.
- `/net/mmx/eso/bin/dumb_persistence_writer`: journals and records the write in `/sim/profile/persistence/`.

In the SD copy, `mibsim` replaces each ARM binary in `apps/sbin/` with a small host wrapper. `sed`, `xxd`, `dd`, `bc`, `cut`, `tee`, `gzip`, and `sha1sum` exec the host tool. `flashit` journals its arguments. If `/sim/profile/flashit.fail` does not exist, it copies the `-f` image into `/net/rcc/dev/fs0p0` at the `-a` offset and prints erase and programming lines in the format recorded in `flashit.log.sample`. `flashlock` and `flashunlock` print the profile text. `pc`, `dumb_persistence_reader`, and `updatePersistence` answer from `/sim/profile/persistence/`. `patcher` journals and copies its input to `<input>_patched.ifs`, with the patched header size taken from the profile. This replacement only happens in the simulator's copy, never in the repository.

The fake unit tree also contains the following. The file `/usr/apps/MIBRoot`, present only with `--node rcc`, which makes `start` believe it runs on the RCC. The directories `/net/rcc/dev/shmem/` and `/net/rcc/tmp/`. `/net/rcc/dev/fs0p0` and `/net/rcc/dev/fs0`, sparse files of the size given in the profile (default 64 MiB) that contain a synthetic IFS image at the profile's offset. `/net/rcc/mnt/efs-persist/FEC/FecContainer.fec`, plus `storage1.raw`, `storage2.raw`, and `SWDL/`. `/net/mmx/mnt/app/eso/hmi/lsd/jars/GEM.jar`, a copy of `mod/gem/GEM412` or of a profile-specific jar. `/net/mmx/mnt/app/eso/hmi/engdefs/`. `/net/rcc/dev/shmem/version.txt`, taken from the profile.

Two profiles are created under `dev/sim/profiles/`. `mhi2` is MHI2 with train `MHI2_ER_SKG13_P4526`, MU `1440`, offset `ba0000`, and stock header size `1C06F300`. These values come from the `beta` branch's `mod/unit_db/unit_db`, row `1440`, and should be cross-checked against a donated backup when one is available. `mhig` is MHIG with train and values taken from the first data row of `patches/MHIG_patch_db.csv`. Both use the made-up VIN `WVWZZZSIMULATED01` and the FAZIT `SIM-FAZIT-0000001`. `dev/sim/make-profile.py` builds `eeprom.bin` from a small text description (`profile.ini`: train, MU, FAZIT, part number, coding, VIN) by writing the ASCII values at the addresses that `config/BASICS` and `config/LOCALS` read: `3A0`/`19`, `3B9`/`4`, `9E`/`17`, `80`/`B`, `BA`/`D`, `12E`/`B`, `96`/`3`, and `F1`/`19`. It also builds the synthetic IFS image: the magic bytes `EB 7E FF 00 01 00 08` at the stage-2 offset (the pattern `apps/offset` searches for), and the little-endian size at byte 36 of the image (`dd bs=4 skip=9`).

Promotion criterion: the prototype is promoted to a permanent tool when both profiles run, without script errors, through `apps/backup -a`, `apps/offset -log`, `apps/vim -s 0 c7`, `apps/svm -f`, `apps/flash -p`, and `apps/flash -r`, and the journal shows the `flashit` call with the offset the profile defines. If the simulated flow diverges because a stub's output format is wrong, correct the stub, not the product script. Record each correction in `Surprises & Discoveries` with the evidence. If the namespace approach proves impossible on some host, the fallback is a Docker container running as root with the same layout. Record which one was used.

### Milestone 3: characterization tests ("golden master")

Scope: freeze today's behaviour so every later change can be checked against it. A "characterization test" does not judge whether behaviour is right. It records what the code does now and fails if that changes. At the end, `dev/test/run.sh` runs every scenario and prints `N passed, 0 failed`.

A scenario is a directory `dev/test/scenarios/<name>/` with the files `cmd` (one line: the command run in the simulator), `profile` (one word: `mhi2` or `mhig`), optionally `setup.sh` (host-side preparation of the profile or SD copy, e.g. putting a patch folder in place or pre-creating a lock file), and the expected outputs `expected.journal`, `expected.stdout`, `expected.log`, and `expected.files` (a sorted list of paths and SHA-1 values of every file created or changed on the SD copy and the fake unit). Before comparison, `dev/test/normalize.sh` removes volatile content such as timestamps, temporary directory names, and elapsed seconds, and replaces the result folder path with `<OUT>`.

Create scenarios in this order. First, one per menu entry: parse both ESD files, take every `script` entry's path, and use the wrapper as `cmd`, so the generated set covers the menu exactly. Next, one per `start` option, fed through standard input. Then failure scenarios for the critical path: `flash -p` with no patch folder, with a patch folder whose header does not match, with an already-patched unit, with too little RAM (MHIG), and with `flashit.fail` set. `flash -r` without a backup. `backup -a` twice, where the second run must skip. Every wrapper started while `flash.mib` exists. Record the list of scenarios and their count in `Progress`.

Also produce `dev/docs/source-graph.txt`, generated by `dev/tools/source-graph.sh`: for every `. <file> <args>` line in `apps/`, `config/`, `start`, and `esd/scripts/`, the caller, the sourced file, the arguments, and the variables the sourced file assigns that the caller later reads. This is the map Milestone 5 must preserve.

Record the goldens with `dev/test/run.sh --record` on `baseline/pre-refactor`. Commit them. From then on, `dev/test/run.sh` without `--record` must pass on every commit. Acceptance: on the unchanged code base, `dev/test/run.sh` prints `passed` for every scenario. Deliberately breaking one line, for example changing `-a $OFFSETPART2` to `-a 0` in `apps/flash`, makes at least the `flash_patch_*` scenarios fail with a readable diff of the journal. Revert the break afterwards.

### Milestone 4: shared library `lib/`

Scope: one place for the logic that is copied everywhere today. At the end, the folder `lib/` exists on the SD card with the files listed in `Interfaces and Dependencies`. `config/GLOBALS`, `config/BASICS`, `config/LOGS`, `config/LOCALS`, `config/MIBCHECK`, and `config/USB` become thin compatibility shims that source `lib/` and set the same variable names as before, so that not-yet-migrated apps keep working unchanged. No app is migrated in this milestone.

Library design rules, which also apply in Milestone 5. Every public function is prefixed with its module name (`log_`, `lock_`, `unit_`, `ui_`, `env_`, `help_`). Functions return status with `return` and hand back values in global variables named in their documentation comment, because Korn-shell command substitution creates a subshell and would lose side effects such as log appends in some paths. Each `lib/*.sh` file guards against double loading with a variable such as `MIB_LIB_LOG_LOADED=1`. `lib/mib.sh` loads the others in dependency order.

The library discovers the SD root once, in `env_detect_volume`. That function keeps the precedence of `config/USB` (`sda0`, then `sdb0`, then `usb0_0`) and never prints when `GEM` is set. Paths to bundled tools are derived from the SD root instead of hard-coding `/net/mmx/fs/sda0`. The expensive EEPROM identity reads move into `unit_load_identity`, which reads each field once and caches it in the same variables as today (`TRAINVERSION`, `MUVERSION`, `FAZIT`, `MIBMO`, and so on). The ten copies of the EEPROM `sed | xxd` pipeline become `unit_e2p_ascii <addr> <len>` and `unit_e2p_hex <addr> <len>`.

`lock_acquire <name>` creates `/net/rcc/dev/shmem/<name>.mib` atomically with `set -o noclobber` and `: > file`, which opens the file with exclusive creation. That closes the check-then-touch race that exists today without changing the file's type or name. `lock_release` removes the file. `lock_busy <name>...` tests others.

`log_*` wraps the repeated `echo -ne ... | $TEE -i -a $LOG`. `log_result` replaces the misnamed `ERROR` function, and `config/LOGS` keeps `ERROR` as an alias for compatibility. `ui_*` centralizes colour codes (suppressed under `GEM`), the countdown, and the GPL notice, which is duplicated in 47 help blocks today. `help_print <revision> <usage-lines>` prints the standard help.

Acceptance: `dev/test/run.sh` passes with zero golden changes, because only the shims changed. `dev/tools/lint.sh` passes, and the ShellCheck count for `config/*` is lower than the baseline. Unit tests for the library, in `dev/test/lib/*.sh`, run under `mksh` on the host without the simulator and cover volume detection precedence, the EEPROM parser (given sample `modifyE2P` text), lock acquire and release, a second acquire failing, and `noclobber` being restored afterwards.

### Milestone 5: migrate the apps (5a, 5b, 5c)

Scope: rewrite each file in `apps/` to use `lib/`, one app per commit, keeping every option, output line, and journal entry identical. The standard skeleton for a migrated app is shown in `Interfaces and Dependencies`.

Migrate in increasing order of risk. Milestone 5a covers the read-only or informational apps: `showlog`, `cleanup`, `hex2ascii`, `crc16`, `eeprom2bin`, `allversions`, `carmodel`, `pers`, `offset`, `rccd`, `mounts`, `showimage`, and `obd` (read part). Milestone 5b covers the apps that write settings: `vim`, `svm`, `carp`, `dmenu`, `aadev`, `amp`, `ambient`, `subwoofer`, `setlang`, `setreg`, `settrain`, `setvariant`, `navon`, `pwset`, `wlan`, `hotspot`, `sshd`, `usbdev`, `edittmc`, `installjava`, `addimage`, `ImageMod`, `delnavdb`, `patch_prep`, `restore`, `backupplus`, and `zlib`. Milestone 5c covers the critical path: `backup`, `addfec`, `fecel`, `flash`, `reboot`, `launcher`, and `gem`. `apps/beta` is an experiment harness and only gets the header change.

Rules for every migration. Keep the `revision=` line and bump its patch version. Keep the file executable bit and the `#!/bin/sh` line. Keep the sourcing edges listed in `dev/docs/source-graph.txt`: where app A sources app B to receive variables, B must still set those variables when sourced. Keep `return 2> /dev/null` at the points where the original used it, because that is how a sourced app hands control back. Do not quote-fix a variable if quoting could change behaviour (for example, a deliberately word-split argument list) without a scenario that exercises it. After each app, run `dev/test/run.sh` and `dev/tools/lint.sh`. If a golden differs, the migration is wrong. Fix the code, not the golden. The only exception is a difference in pure whitespace in `expected.stdout` that a user cannot see, and even that needs a Decision Log entry.

Acceptance per sub-milestone: all scenarios pass, the lint ratchet shows fewer findings, and `grep -c 'export PATH=' apps/*` shows 0 for every migrated app. At the end of 5c, `grep -rn '/net/mmx/fs/sda0' apps/` finds only the paths that must stay literal: the menu link target in `launcher` and `gem`, each with a comment explaining why.

### Milestone 6: generated menu wrappers and menu consistency checks

Scope: stop hand-copying the 88 files in `esd/scripts/`. At the end, `dev/esd/manifest.txt` holds one line per wrapper, and `dev/esd/generate.sh` writes all wrappers from it. The generated wrappers source `lib/esd.sh`, whose `esd_run` prints the banner, checks the locks, sets `GEM=1`, and runs the command. Their paths and file names stay identical.

Also add `dev/esd/check.sh`. It fails if an ESD file references a script that does not exist, or if the version label in either ESD file differs from the first word of `VERSION`. It fails if the MHI2 ESD file claims "MHIG Edition". It fails if any `esd/*.esd` file is not CRLF or any wrapper is not LF. It warns, without failing, about unreferenced wrappers.

The currently broken references (`backupplus_speech.sh`, `XXXX.sh`, `xxx.sh`) and the wrong labels are fixed in Milestone 7, not here, so this milestone stays behaviour-neutral. Until then, `check.sh` reads a small allow-list `dev/esd/known-issues.txt`, which Milestone 7 empties.

The manifest has five tab-separated fields per line: the wrapper file name, the header comment, the space-separated lock names that block starting (or `-`), the node prefix (`rcc`, `mmx`, or `-`), and the command line. Wrappers with extra logic, such as `patch_aio.sh`, `backupplus_all.sh`, `rsdb.sh`, `udevice.sh`, `custom.sh`, and `abackup.sh`, are marked `custom`. For those, the generator copies a hand-written body from `dev/esd/custom/<name>.sh` and only prepends the standard header.

Acceptance: running `dev/esd/generate.sh` on a clean checkout produces no `git diff` beyond the intended normalization of the headers. All menu scenarios from Milestone 3 pass unchanged. `dev/esd/check.sh` exits 0 with the allow-list.

### Milestone 7: deliberate safety fixes

Scope: fix the defects found during analysis. Do each one as its own commit in this pattern. First add a scenario that shows the defect and currently records the wrong behaviour. Then fix the code. Then re-record only that scenario's golden with `dev/test/run.sh --record <scenario>`. Finally add a Decision Log entry that names the scenario. The fixes, in priority order:

1. Verify after write. After `flashit` in `apps/flash`, read the written range back from `/net/rcc/dev/fs0p0` with the bundled `dd` (skip = offset / 4096, count = size / 4096 rounded up, then `head -c size`) and compare its SHA-1 with the image's SHA-1. On mismatch, show the existing "Flash validation FAILED ... DO NOT reboot" text, do not reboot, and exit 1. Keep the old heuristic as an additional check. Scenario: `flash_patch_readback_mismatch`, where the `flashit` stub writes one corrupted byte.
2. Validate the image before a restore. In `apps/flash -r`, before flashing the backup image, check three things: the file size is at least the header size, the header magic bytes are present, and the header size equals `STAGE2SIZE` as reported by `offset`, or equals the stock value in `patches/MHIG_patch_db.csv` for MHIG. Refuse with a clear message otherwise. Scenario: `flash_restore_truncated_backup`.
3. Atomic backups. In `apps/backup`, write each file to `<name>.part` and rename it to the final name only after the copy succeeds and its size is non-zero. Then an interrupted backup is retried on the next run instead of being treated as complete, and `flash -p`'s completeness check becomes trustworthy. Existing complete backups are not touched. Scenarios: `backup_interrupted_then_resumed` and `backup_existing_untouched`.
4. The correct menu file on MHIG. Make `apps/gem -i` use the same model-based choice as `apps/launcher`, through one shared library function `gem_install_link`. Scenario: `start_G_on_mhig`.
5. Normalize the flash offset and fix the hex arithmetic. In `apps/offset`, upper-case the scanned `xxd` offset before passing it to `bc`. Normalize `OFFSETPART2` once, lower case for comparisons and file names, and upper case whenever it goes to `bc` (in `apps/offset` `BLOCKS`, `apps/flash` `DDCALC`, and `apps/backup`). Compare it against `patches/MHIG_patch_db.csv` case-insensitively. Keep the allow-list (`ba0000 bc0000 be0000 c00000 c20000`), but check it in one place instead of the ten-branch comparison in `IFSstage2`. This resolves the TODO in `apps/flash` line 61 and the three defects in `Surprises & Discoveries`. Scenarios: `offset_scan_be0000` (expects `be0000` and the real size), `flash_patch_mhig_ok` (reaches `flashit`), and `flash_restore_wrong_offset_refused` (the allow-list still refuses `540000`). Treat this as the highest-risk fix of Milestone 7, because it turns a path that always stops into one that flashes. Validate it on a bench MHIG unit before release.
6. Exit codes. Make failure paths in `flash`, `backup`, `offset`, and `svm` exit or return non-zero. Make `esd/scripts/patch_aio.sh` stop the all-in-one sequence when `backup -a` fails. Scenario: `aio_stops_after_backup_failure`. Before changing this, check in the source graph that no caller relies on the old exit status 0.
7. Menu clean-up. Remove the dead menu entries that point at missing scripts (`backupplus_speech.sh`, `XXXX.sh`, `xxx.sh`), or add the missing wrapper if the intended command is clear from `apps/backupplus` (it has a `-speech` option, so add a `backupplus_speech.sh` wrapper that runs `apps/backupplus -speech`). Set both version labels from `VERSION`. Make the MHI2 label read "MHI2 Edition". Empty `dev/esd/known-issues.txt`.

Acceptance: every new scenario fails on `baseline/pre-refactor` and passes on the branch, and every other scenario is unchanged.

### Milestone 8: continuous integration and release packaging

Scope: automate everything above for every push and pull request. Add `.github/workflows/ci.yml` with one job on `ubuntu-22.04` that runs `dev/tools/install-deps.sh`, `dev/tools/lint.sh`, `dev/esd/check.sh`, `dev/test/run.sh`, `dev/tools/check-frozen.sh`, and `dev/tools/package.sh`, and uploads the zip as a build artifact. Unprivileged user namespaces are available on GitHub's Ubuntu runners. If a runner denies them, the job falls back to `sudo` with the same script.

`dev/tools/check-frozen.sh` fails when any of the following holds: the SHA-1 of `Launcher/final/finalScript.sh` differs from `FinalScriptChecksum` in `metainfo2.txt`; the SHA-1 of `Launcher/version/MIB` differs from its `CheckSum`; `metainfo2.txt` is not CRLF; or any binary listed in `dev/binaries.sha1` has a different checksum. `dev/binaries.sha1` is created with `sha1sum` over `apps/sbin/*`, `apps/sbin/beta/*`, `mod/gem/*`, `mod/java/*`, and the binaries in `mod/sshd/usr/**`.

Replace the old `tests/` folder. Move its README's still-relevant manual flash instructions into `dev/docs/hardware-test.md`, created in Milestone 9, and delete `tests/test_lock_files.sh` and `tests/quick_check.sh`. They are superseded by the lock scenarios and the library lock tests. Record this in the Decision Log.

Acceptance: a pull request that changes one byte in `Launcher/final/finalScript.sh` fails CI with the message `finalScript.sh checksum does not match metainfo2.txt`. A clean pull request passes.

### Milestone 9: hardware validation and pre-release

Scope: prove on real hardware what the simulator cannot. A "bench unit" is a head unit on a desk with a laboratory power supply (13.5 V, at least 10 A), a serial console connection to the RCC, and a known-good full backup. It is not a customer car. Write `dev/docs/hardware-test.md`, a protocol with one row per step, filled in during testing.

Run the protocol on at least one MHI2 unit and one MHIG unit, in this order: install via the software update (SWDL) and confirm that the engineering menu shows the M.I.B. entry with the correct version label; run the read-only entries; run `backup -a` twice and compare folder checksums; run the reversible settings (`vim` 199, then back to 6; `dmenu`; ambient light patch and restore); and only then run flash patch and flash restore, with recovery equipment ready. Attach the unit logs to the test record after removing the VIN and FAZIT.

Publish a GitHub pre-release built by `dev/tools/package.sh`, labelled as a test build, and collect at least ten community reports across MHI2, MHI2Q, and MHIG before tagging a normal release. Acceptance: the protocol file is committed with results, and the pre-release exists.


## Concrete Steps

All commands run from the repository root `/home/marco/Code/mibfork` (any clone works) in a Linux shell, unless a step says otherwise. Every step is safe to repeat.

Milestone 0:

    git fetch --all --tags
    git tag -f baseline/pre-refactor 3f3caeb
    git tag -f archive/beta-2022-11 origin/beta
    git remote get-url upstream 2>/dev/null || git remote add upstream https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash.git
    git fetch upstream
    git switch -c refactor/core 2>/dev/null || git switch refactor/core
    git tag -l 'baseline/*' 'archive/*'

Expected output of the last command:

    archive/beta-2022-11
    baseline/pre-refactor

Push the tags (`git push origin baseline/pre-refactor archive/beta-2022-11`) only after the repository owner agrees.

Milestone 1 (after writing the scripts described in Plan of Work):

    dev/tools/install-deps.sh               # installs into dev/.tools/, no root needed
    dev/tools/lint.sh --update-baseline      # once, on the unchanged code; commit dev/lint/shellcheck-baseline.txt
    dev/tools/lint.sh

Expected output on an unchanged tree:

    mksh -n: 150 files OK
    shellcheck: 3444 findings, 0 new, 0 fixed (baseline 3444)
    OK

The file count was 150 at `3f3caeb` plus Milestone 1.

Packaging:

    dev/tools/package.sh
    unzip -l dist/MIB-V3.7.3.zip | grep -cE ' (dev|tests|\.agent)/'

Expected: `0`.

Milestone 2:

    dev/sim/mibsim --profile mhi2 -- /net/mmx/fs/sda0/apps/offset -log
    cat dev/sim/out/latest/stdout

Expected (the MHI2 profile has `flashlock` with the image at `ba0000`):

    mibsim: exit 0 - results in dev/sim/out/<timestamp>-<pid>
    Using SD1...

    ifs-root-stage2.ifs offset: 0x00ba0000
    ifs-root-stage2.ifs size: 1C06F300

    dev/sim/mibsim --profile mhi2 -- /net/mmx/fs/sda0/apps/vim -s 0 c7
    cat dev/sim/out/latest/journal

Expected (tab-separated):

    mount	-uw	/net/mmx/fs/sda0
    updatePersistence	-key	3221422082	-ns	0	-type	b	-value	C70000000000000000000000000000000000000000000000000000009F29
    updatePersistence	-key	1	-ns	0	-type	b	-value	0
    mib2_ioc_flash	reboot

A scenario setup script gets `SIM_SD`, `SIM_UNIT`, `SIM_PROFILE`, and the `PROFILE_*` variables. For example, this places a pre-made MHI2 patch so that `flash -p` reaches `flashit`:

    d="$SIM_SD/patches/${PROFILE_TRAIN}_${PROFILE_MU}_PATCH"; mkdir -p "$d"
    cp "$SIM_PROFILE/stage2-patched.ifs" "$d/${PROFILE_MU}-ifs-root-part2-0x00${PROFILE_OFFSET}-${PROFILE_HEADER}.ifs"

With that setup, `dev/sim/mibsim --profile mhi2 --setup <file> -- /net/mmx/fs/sda0/apps/flash -p` prints "OK: Flash checked and valid", and its journal contains `flashunlock`, `flashit -v -d -x -a ba0000 -p /net/rcc/dev/fs0 -f .../MU1440-ifs-root-part2-0x00ba0000-1C06F300.ifs`, and finally `mib2_ioc_flash reboot`.

Milestone 3:

    dev/test/gen-menu-scenarios.sh          # creates dev/test/scenarios/menu_* from both ESD files
    git switch --detach baseline/pre-refactor
    dev/test/run.sh --record
    git switch refactor/core
    dev/test/run.sh

Expected tail of the last command:

    ...
    PASS  menu_mhi2_vim199
    PASS  flash_patch_mhi2_ok
    PASS  flash_patch_mhig_ok
    ----
    <N> passed, 0 failed

Milestones 4 to 7: after every commit run

    dev/tools/lint.sh && dev/esd/check.sh && dev/test/run.sh

and expect `OK`, `OK`, and `<N> passed, 0 failed`. Also sync with upstream before each milestone:

    git fetch upstream && git rebase upstream/main

If the rebase conflicts in a file already migrated, apply the upstream change's intent to the migrated file. Then add a scenario for the upstream change so it stays covered.


## Validation and Acceptance

The whole plan is accepted when all of the following are true and demonstrated.

On a Linux host, `dev/tools/install-deps.sh && dev/tools/lint.sh && dev/esd/check.sh && dev/test/run.sh && dev/tools/check-frozen.sh` exits 0. The test summary shows at least one scenario per menu entry in both ESD files, one per `start` option, and the critical-path failure scenarios listed in Milestones 3 and 7.

`git diff baseline/pre-refactor -- metainfo2.txt Launcher/final Launcher/version` is empty.

For every scenario that is not in the Milestone 7 list, `expected.journal` is byte-identical to the one recorded on `baseline/pre-refactor`. `git diff baseline/pre-refactor -- dev/test/scenarios/*/expected.journal` shows changes only in scenarios named in the Decision Log.

The ShellCheck count is at most half of the 3,444 baseline findings, and there are 0 new findings.

The duplication is gone: `grep -l 'export PATH=' apps/* esd/scripts/*.sh | wc -l` prints 0 (the environment is set only in `lib/env.sh`), and `grep -c 'Free Software Foundation' apps/*` finds the GPL text in no app (it lives in `lib/help.sh`).

The hardware protocol in `dev/docs/hardware-test.md` is completed for one MHI2 and one MHIG bench unit, and a pre-release zip built by CI is published.


## Idempotence and Recovery

Every tool this plan adds is repeatable. `mibsim` always works on a fresh copy in a new result folder and never writes to the checkout. `run.sh --record` overwrites only the goldens of the named scenarios. The generator in Milestone 6 rewrites the wrappers deterministically. The tags in Milestone 0 are created with `-f` and point at fixed commits.

If a migration in Milestone 5 goes wrong, revert that single commit (`git revert <sha>`). Each app is its own commit for exactly this reason. If the simulator itself turns out to be wrong (it disagrees with a real unit log), fix the stub, re-record the goldens on `baseline/pre-refactor` (`git switch --detach baseline/pre-refactor && dev/test/run.sh --record`), switch back, and re-run. That keeps the goldens anchored to the original code, never to refactored code.

Nothing in Milestones 0 to 8 touches a real head unit. Milestone 9 does. There, the rule is to always have a complete backup (the folder created by `apps/backup -a`, including `<MU>-RCC_fs0.bin` and `<MU>-EEProm.bin`) copied off the SD card to a PC before any flash step, to use the bench power supply, and to stop at the first unexpected message. As the existing flash failure text says, a failed flash does not take effect as long as the unit is not rebooted or powered down.

The simulator uses unprivileged namespaces and a `tmpfs`, so all its mounts vanish when the process ends. If a run is interrupted, `rm -rf dev/sim/out/<folder>` is the only cleanup.


## Artifacts and Notes

Simulator feasibility prototype (2026-09-25, Ubuntu 22.04 on WSL2, kernel 6.18). The repository was bound at the head-unit SD path inside an unprivileged namespace with no changes to any script. In this prototype, R was a scratch folder, and the host's /usr, /bin, /lib, /lib64 and /etc were bind-mounted or symlinked into it first:

    unshare --user --map-root-user --mount sh -c '
      mount -t tmpfs none $R && ... &&
      mkdir -p $R/net/mmx/fs/sda0 $R/net/rcc/dev/shmem &&
      mount --bind /home/marco/Code/mibfork $R/net/mmx/fs/sda0 &&
      chroot $R /bin/sh -c "cat /net/mmx/fs/sda0/VERSION; echo chroot-sim OK"'
    V3.7.3 "long time ago..."
    chroot-sim OK

(The permanent simulator binds a copy, never the checkout.)

Menu consistency scan on `main` at `3f3caeb`:

    referenced but missing: esd/scripts/XXXX.sh, esd/scripts/backupplus_speech.sh, esd/scripts/xxx.sh
    unreferenced:           b2nand.sh backup.sh bfecel.sh conversion_fix_eu.sh patch.sh settrain.sh showimage_test.sh

Frozen checksums on `main` at `3f3caeb`:

    ba391875e14a8794b683cc02556990fcb555fe08  Launcher/final/finalScript.sh   (= metainfo2.txt FinalScriptChecksum)
    dd0d39ca3e257d4a71d59c3508afee5b0dc0ebdf  Launcher/version/MIB            (= metainfo2.txt CheckSum)

ShellCheck baseline, `shellcheck -s ksh -f gcc` over all shell sources:

    3444 findings: 4 error, 240 warning, 3200 note
    top codes: SC2086 2655, SC2317 199, SC2027 137, SC1091 130, SC2034 65, SC2002 53

Duplication and hard-coding counts:

    esd/scripts with identical PATH/LD_LIBRARY_PATH block: 88 of 88
    apps with their own PATH export: 48; apps with a full GPL help text: 47
    literal "/net/mmx/fs/sda0" outside apps/sbin: 434 (195 of them in the two ESD files, which must stay literal)


## Interfaces and Dependencies

Host tools (developer machine and CI only, never on the unit): `mksh` (the reference shell), `shellcheck` 0.8 or newer, `bash` 5 (for `dev/` scripts only), `python3` 3.10 or newer (for `dev/sim/make-profile.py` only), `bc`, `xxd`, `util-linux` (`unshare`), `git`, `zip`/`unzip`. On the unit, only the QNX shell and the binaries already shipped in `apps/sbin/` are used. No new binary is added.

`lib/mib.sh` is the single entry point. An app loads it with `. "$thisdir/../lib/mib.sh"`. Loading sources, in this order, `lib/env.sh`, `lib/log.sh`, `lib/lock.sh`, `lib/unit.sh`, `lib/ui.sh`, `lib/help.sh`, and `lib/gem.sh`. Loading has no side effects beyond defining functions and constants. `mib_init` performs the work that `config/GLOBALS` performs today, in the same order: USB remount, SD write test, tool paths, identity, model, backup folder, log header. `mib_init` returns immediately if `LOG` is already set, matching the existing `if [ -z $LOG ]` guard.

The public functions at the end of Milestone 4 are:

    # lib/env.sh
    env_setup_path                 # exports PATH, LD_LIBRARY_PATH, IPL_CONFIG_DIR exactly as the apps do today
    env_detect_volume              # sets VOLUME (sda0 > sdb0 > usb0_0 > "."); silent if GEM is set
    env_define_tools               # sets SED XXD DD BC CUT TEE GZIP SHA1 RDIFF PATCHER PC PERSR PERSW UDP E2P FLASHIT FLASHLOCK FLASHUNLOCK TIMESTAMP TMP fs0p0 VERSIONS

    # lib/log.sh
    log_open                       # creates BACKUPFOLDER and LOG with the header written today by config/LOGS
    log_line  <text>               # appends to LOG only
    log_say   <text>               # prints and appends (echo -ne text | $TEE -i -a $LOG)
    log_result                     # prints " -> done :-)" or " -> failed!" from the caller's last status; ERROR remains an alias
    log_section <name>             # writes "\n$ME-<name>---->\n" as the apps do today

    # lib/lock.sh
    lock_acquire <name>            # atomically creates $TMP/<name>.mib; returns 1 if it exists; restores the previous noclobber state
    lock_release <name>
    lock_busy <name>...            # returns 0 if any of the named locks exists
    lock_release_on_exit <name>    # installs the EXIT/TERM trap used today by cleanup_flash, cleanup_svm, cleanup_backup

    # lib/unit.sh
    unit_e2p_ascii <hexaddr> <hexlen>   # sets UNIT_VALUE to the printable ASCII string, identical to today's pipeline output
    unit_e2p_hex   <hexaddr> <hexlen>   # sets UNIT_VALUE to concatenated lower-case hex, identical to MODELID/CODING today
    unit_load_identity                  # sets TRAINVERSION MUVERSION FAZIT MIBMO ME ON (once; cached)
    unit_load_details                   # sets VINCAR VINMIB MODELID MODEL PARTNO COMPONENT VARIANT DATASETV HWNO CODING (config/LOCALS)
    unit_require_model <mibcap>         # replaces MIBCAP=..; . config/MIBCHECK with identical messages and exit 1

    # lib/ui.sh
    ui_color <name>                # prints the escape sequence, or nothing when GEM is set
    ui_countdown <seconds>         # the "10 seconds left...9...8" pattern used in flash
    ui_back                        # prints "You can go back now...\n"

    # lib/help.sh
    help_print <revision> <option-line>...   # the standard usage block followed by the GPL notice

    # lib/gem.sh (Milestone 7)
    gem_install_link               # chooses Launcher-MHIG-sda0.esd or Launcher-sda0.esd by TRAINVERSION and links it
    gem_remove_link

    # lib/esd.sh (Milestone 6)
    esd_run <locks|-> <node|-> <command...>   # banner, lock check, GEM=1, run, footer "All done! now you can go back..."

The standard migrated app skeleton (Milestone 5) looks like this, shown as an indented example:

    #!/bin/sh
    revision="<name> v<x.y.z> (<date> by <author>)"
    thisname="$(basename $0)"
    thisdir="$(dirname $0)"
    . "$thisdir/../lib/mib.sh"
    env_setup_path
    mib_init && log_section "$thisname"
    lock_busy "$thisname" reboot && { echo "$thisname or reboot is already running..."; return 2> /dev/null; }
    unit_require_model 3
    case $1 in
        -x) ... ;;
        *) help_print "$revision" "-x   does something" ;;
    esac
    exit 0

The `modifyE2P` text format that the simulator stub must emit is inferred from the parser in `config/BASICS` (`s/^0x\S+\W+(.*?)$/\1/`, followed by pairs of hex digits). Each line is an address starting with `0x`, followed by a separator and up to 16 space-separated two-digit hex bytes, for example `0x000003a0: 4d 48 49 32 5f 45 52 5f 53 4b 47 31 33 5f 50 34`. This is an assumption. Confirm it against a real `<MU>-EEProm.txt` from any donated backup (`apps/backup` writes the raw `modifyE2P r 0 8000` output to that file) before recording goldens, and record the confirmation in `Surprises & Discoveries`.

Scenario directory contract (Milestone 3): the files are `cmd`, `profile`, optional `setup.sh`, optional `stdin`, and `expected.{journal,stdout,log,files}`. `dev/test/run.sh [--record] [scenario...]` prints `PASS <name>` or `FAIL <name>` followed by a unified diff, then the summary line `<N> passed, <M> failed`. It exits with a non-zero status if any scenario fails.

Manifest line format (Milestone 6), tab-separated, with `#` comments allowed:

    <wrapper.sh>  <header comment>  <blocking locks or ->  <rcc|mmx|->  <command line | custom>


Revision note (2026-09-25): initial version, written after analysing `main` at `3f3caeb` and `origin/beta` at `144bf83`, including a ShellCheck baseline and a working namespace-simulator prototype.

Revision note (2026-09-25, later): Milestones 0 to 2 were executed. The plan now records the simulator as built (worktree SD source, tmpfs-of-symlinks `/usr`, four profiles), the MHIG offset case and hex defects found with it, the safety role of the offset allow-list, and an expanded Milestone 7 item 5.
