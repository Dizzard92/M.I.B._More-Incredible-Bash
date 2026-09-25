# dev/ — developer tooling (not part of the SD card)

Everything in this folder runs on a developer PC or in CI, never on the head unit.
`.gitattributes` marks `dev/` as `export-ignore`, so `dev/tools/package.sh` (and any
`git archive`) leaves it out of the package that users copy to their SD card.

The refactoring plan that introduced this folder is `.agent/execplans/mib-refactor.md`.

## Setup

    dev/tools/install-deps.sh

This installs `mksh`, `shellcheck`, `bc` and `xxd` into `dev/.tools/bin` (git-ignored)
without root. Tools already on your `PATH` are reused. It needs Debian/Ubuntu
(`apt-get download`) and internet access. The dev scripts put `dev/.tools/bin` on `PATH`
themselves.

## Commands

- `dev/tools/lint.sh` runs `mksh -n` over every head-unit shell source, then ShellCheck,
  compared against `dev/lint/shellcheck-baseline.txt`. Any new finding fails the run.
  When findings go down, run `dev/tools/lint.sh --update-baseline` and commit the baseline.
- `dev/tools/shell-sources.sh` lists the files that lint and CI treat as head-unit shell code.
- `dev/tools/package.sh [commit]` builds `dist/MIB-<version>.zip`. It fails if developer
  files would be packaged or if required files are missing.

## Head-unit simulator

    dev/sim/mibsim --profile mhi2 -- /net/mmx/fs/sda0/apps/offset -log
    cat dev/sim/out/latest/stdout dev/sim/out/latest/journal

`dev/sim/mibsim` runs any M.I.B. script against a simulated unit. It needs no root and
no hardware: an unprivileged user and mount namespace plus a `chroot` whose paths look like
the unit's (`/net/mmx/fs/sda0` = a copy of the SD card, `/net/rcc/...` = the RCC). QNX tools
are stubs in `/proc/boot`, and `/bin/sh` is `mksh`. The ARM binaries in `apps/sbin` are
replaced in the copy by host tools or stubs. Every command that would change the unit
(flash, EEPROM or persistence write, remount, reboot) is written to `journal`. `changes`
lists every file that was added or modified on the SD card and the unit. `mibsim --help`
lists the options.

Profiles live in `dev/sim/profiles/<name>/profile.ini`. `dev/sim/make-profile.py` turns them
into EEPROM, flash and persistence contents at run time, so no binary fixtures and no real
unit data (VIN, FAZIT) are stored in git:

- `mhi2`: MHI2, MU1440, stage 2 at `ba0000`, with `flashlock`.
- `mhig`: MHIG, fictional firmware 9999, stage 2 at `ba0000`, with `flashlock`.
- `mhig-scan-ba0000` and `mhig-scan-be0000`: MHIG without `flashlock`. They exercise
  the flash scan in `apps/offset`.

Output formats of the unit tools (`modifyE2P`, `flashlock`, `flashit`, persistence) are
inferred from the parsers in `apps/` and `config/`. Correct a stub when a real unit log
disagrees; never change a product script to fit a stub.

## Why mksh

The head unit runs QNX, whose `/bin/sh` is a Korn shell. `mksh` is the closest shell
available on Linux. `bash -n` accepts many constructs the unit rejects. Do not use
`local`, `declare`, `mapfile`, `${v,,}`, `<<<`, process substitution or `[[ =~ ]]` in
code that runs on the unit. The `dev/` scripts themselves are bash and may use them.

## Frozen files

Do not edit `metainfo2.txt`, `Launcher/final/finalScript.sh`, `Launcher/final/hashes.txt`
or `Launcher/version/MIB`. The unit's software-download process checks their SHA-1 checksums.
