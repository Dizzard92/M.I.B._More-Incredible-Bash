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

## Why mksh

The head unit runs QNX, whose `/bin/sh` is a Korn shell. `mksh` is the closest shell
available on Linux. `bash -n` accepts many constructs the unit rejects. Do not use
`local`, `declare`, `mapfile`, `${v,,}`, `<<<`, process substitution or `[[ =~ ]]` in
code that runs on the unit. The `dev/` scripts themselves are bash and may use them.

## Frozen files

Do not edit `metainfo2.txt`, `Launcher/final/finalScript.sh`, `Launcher/final/hashes.txt`
or `Launcher/version/MIB`. The unit's software-download process checks their SHA-1 checksums.
