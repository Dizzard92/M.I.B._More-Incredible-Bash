# Notes on the `beta` branch (analysis of 2026-09-25)

The branch is preserved as the tag `archive/beta-2022-11` (commit `144bf83`). It was not
merged into the refactor. See the Decision Log in `.agent/execplans/mib-refactor.md`.

## Shape

`origin/beta` forked from `main` on 2022-08-31. At the time of analysis it was 5 commits
ahead of `main` and 452 behind (`main` at `3f3caeb`).

Commits unique to `beta`, all by harman-f:

- `de1328b` (2022-10-02) "unit DB" adds `mod/unit_db/unit_db`, a semicolon-separated table
  of five MHI2 firmware versions (MU, train, model bytes, stock and patched ifs-root-stage2
  header sizes and SHA-1 values).
- `933056a` (2022-10-02) "model conversion tool" adds `apps/modelconversion`, which parses
  that table into the `UNITDB[1..19]` array and rewrites EEPROM model bytes.
- `b1f637b` (2022-10-02) "Flash live patch" and `279943d` (2022-10-08) "Live PATCH BETA"
  add a live-patch path to `apps/flash` (dump the stock image, patch it with
  `apps/sbin/patcher`, compare the result with the table). The commit message says:
  "Flash script still in debug mode. No flash will be conducted." Debug overrides such
  as `STAGE2SIZE=${UNITDB[15]} #debug test` are still in the code. This commit also adds
  `apps/ascii2hex`, `apps/rdiff`, and `patch_2_3_FEC_*.pattern`.
- `144bf83` (2022-11-16) "added Korea region" changes `metainfo2.txt`: `region7` goes from
  `RoW` (a duplicate of `region2`) to `Korea`, and "FREE for all" is removed from
  `release`, `DeviceDescription` and `DisplayName`.

## What happened on `main` since then

- Live patching was re-implemented for MHIG units: `DB_PARSER` in `apps/flash` reads
  `patches/MHIG_patch_db.csv`, generates the image with `apps/sbin/patcher` and
  `mod/patch_pattern/patch_2_3_FEC_CP.pattern`, and verifies the SHA-1 values before flashing.
- `apps/sbin/patcher`, `apps/sbin/rdiff` and the pattern files exist on `main`.
- `beta` lacks `tests/`, `mod/sshd`, `mod/tmc`, most images, `patches/EL`,
  `patches/MHIG_patch_db.csv` and many apps. Merging it would delete them.

## Open items worth a separate, hardware-validated change

- `region7 = "Korea"` in `metainfo2.txt`. Porsche Korea FEC lists exist
  (`patches/addFec/MHI2/PO/KR`), so Korean units are a real audience. `metainfo2.txt` is
  read by the unit's installer, so this needs a test on a Korean-region unit.
- A table of known stock and patched checksums for MHI2 firmware, like the MHIG CSV, would
  let `apps/flash` verify MHI2 patch files too. The five rows in `mod/unit_db/unit_db` on
  `beta` are a starting point; `git show archive/beta-2022-11:mod/unit_db/unit_db`.
