#!/usr/bin/env python3
"""Builds the fake head-unit state for dev/sim/mibsim from a profile.ini.

Usage: make-profile.py <profile.ini> <output-dir>

Writes into <output-dir>:
  eeprom.bin          32 KiB EEPROM with identity fields at the addresses config/BASICS
                      and config/LOCALS read (train 3A0, MU 3B9, FAZIT 9E, ...)
  fs0.img             RCC flash (fs0 / fs0p0) with a stock ifs-root-stage2 at the profile offset
  stage2-stock.ifs    that stock image
  stage2-patched.ifs  the image the patcher stub produces from it (see lib/ifs.py)
  version.txt         /net/rcc/dev/shmem/version.txt
  flashlock.txt       output of the flashlock tool (only if flashlock = yes)
  FecContainer.fec    FEC container with the VIN at byte 20
  persistence/        values served by the persistence stubs
  mhig_db_row.csv     a patches/MHIG_patch_db.csv row for this synthetic firmware (MHIG only)
  profile.env         shell variables describing the profile (sourced by mibsim and tests)

Every byte is derived from profile.ini, so runs are reproducible and no personal data
from real units is needed. The formats of modifyE2P, flashlock and the persistence tools
are inferred from the parsers in apps/ and config/ (see the ExecPlan).
"""
import configparser
import hashlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import ifs  # noqa: E402

EEPROM_SIZE = 0x8000

# address, length (both as used by config/BASICS and config/LOCALS), profile key, padding
ASCII_FIELDS = [
    (0x3A0, 0x19, "train", b" "),
    (0x3B9, 0x04, "mu", b" "),
    (0x09E, 0x17, "fazit", b" "),
    (0x080, 0x0B, "partno", b" "),
    (0x0BA, 0x0D, "component", b" "),
    (0x12E, 0x0B, "dataset", b" "),
    (0x096, 0x03, "hwno", b" "),
]


def ascii_field(value: str, length: int, pad: bytes) -> bytes:
    raw = value.encode("ascii")
    if len(raw) > length:
        raise SystemExit(f"value {value!r} longer than {length} bytes")
    return raw + pad * (length - len(raw))


def main(ini_path: str, out: str) -> None:
    cp = configparser.ConfigParser(delimiters=("=",))
    cp.read(ini_path)
    unit, flash = cp["unit"], cp["flash"]
    os.makedirs(os.path.join(out, "persistence"), exist_ok=True)

    # EEPROM
    eeprom = bytearray(b"\xff" * EEPROM_SIZE)
    for addr, length, key, pad in ASCII_FIELDS:
        eeprom[addr:addr + length] = ascii_field(unit[key], length, pad)
    coding = bytes.fromhex(unit["coding"])
    if len(coding) != 0x19:
        raise SystemExit("coding must be 25 bytes (50 hex digits)")
    eeprom[0xF1:0xF1 + 0x19] = coding
    open(os.path.join(out, "eeprom.bin"), "wb").write(eeprom)

    # Flash
    offset = int(flash["stage2_offset"], 16)
    stock = ifs.make(ifs.le_hex_to_size(flash["stage2_header"]))
    patched = ifs.patch(stock)
    size = len(stock)
    fs0 = os.path.join(out, "fs0.img")
    with open(fs0, "wb") as f:
        f.truncate(int(flash.get("size_mib", "32")) * 1024 * 1024)
        f.seek(offset)
        f.write(stock)
    open(os.path.join(out, "stage2-stock.ifs"), "wb").write(stock)
    open(os.path.join(out, "stage2-patched.ifs"), "wb").write(patched)

    # flashlock listing: offset in columns 27-32, size in decimal inside the second "(...)"
    if flash.getboolean("flashlock", fallback=False):
        lines = [
            " 1 image type=1(IPL     ) 000000 len (262144)",
            " 2 image type=2(IFS     ) 040000 len (8126464)",
            f" 3 image type=2(IFS     ) {offset:06x} len ({size})",
            " 4 image type=3(EFS     ) f00000 len (1048576)",
        ]
        open(os.path.join(out, "flashlock.txt"), "w").write("\n".join(lines) + "\n")

    # version.txt: "Variant = '...'" (config/LOCALS) and an RCC ifs-root line (apps/flash DB_PARSER)
    open(os.path.join(out, "version.txt"), "w").write(
        f"Variant = '{unit['variant']}'\n"
        f"RCC|ifs-root|{unit['hwno']}|App|{unit['ifs_version']}_0001|\n"
        f"MMX|ifs-root|{unit['hwno']}|App|{unit['ifs_version']}_0001|\n"
    )

    # FEC container: VIN at byte 20 (config/LOCALS reads 17 bytes from offset 20)
    fec = bytearray(b"\x00" * 64)
    fec[20:37] = unit["vin"].encode("ascii")
    open(os.path.join(out, "FecContainer.fec"), "wb").write(fec)

    # persistence values, one file per key: <tool>/<key>
    pers = cp["persistence"] if cp.has_section("persistence") else {}
    for key, value in pers.items():
        tool, _, name = key.partition(".")
        d = os.path.join(out, "persistence", tool)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, name.replace(":", "_")), "w").write(value.strip() + "\n")

    # SVM challenge (apps/svm -f): zlib-compressed 2-byte random value from profile [unit] svm_rand
    import zlib
    open(os.path.join(out, "CfgAckRand.z"), "wb").write(zlib.compress(bytes.fromhex(unit.get("svm_rand", "1234"))))

    stock_sha1 = hashlib.sha1(stock).hexdigest()
    patched_sha1 = hashlib.sha1(patched).hexdigest()
    patched_header = ifs.size_to_le_hex(len(patched))

    if unit["model"] == "mhig":
        # ifs-root_version;stage2_offset;header_chk_orig;SHA1_orig;header_chk_FEC_CP;SHA1_FEC_CP;...
        row = ";".join([unit["ifs_version"], f"{offset:06x}", flash["stage2_header"].upper(), stock_sha1,
                        patched_header, patched_sha1, patched_header, patched_sha1, patched_header, patched_sha1])
        open(os.path.join(out, "mhig_db_row.csv"), "w").write(row + "\n")

    env = {
        "PROFILE_MODEL": unit["model"],
        "PROFILE_TRAIN": unit["train"],
        "PROFILE_MU": "MU" + unit["mu"],
        "PROFILE_FAZIT": unit["fazit"],
        "PROFILE_OFFSET": f"{offset:06x}",
        "PROFILE_HEADER": flash["stage2_header"].upper(),
        "PROFILE_PATCHED_HEADER": patched_header,
        "PROFILE_STOCK_SHA1": stock_sha1,
        "PROFILE_PATCHED_SHA1": patched_sha1,
        "PROFILE_FLASHLOCK": "yes" if flash.getboolean("flashlock", fallback=False) else "no",
        "PROFILE_FREE_RAM_MB": unit.get("free_ram_mb", "300"),
        "PROFILE_IFS_VERSION": unit["ifs_version"],
    }
    with open(os.path.join(out, "profile.env"), "w") as f:
        for k, v in env.items():
            f.write(f"{k}='{v}'\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
