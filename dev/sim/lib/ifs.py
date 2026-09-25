#!/usr/bin/env python3
"""Synthetic QNX IFS images for the M.I.B. head-unit simulator.

The real ifs-root-stage2 image is proprietary. M.I.B. only looks at three things:
  * the magic bytes EB 7E FF 00 01 00 08 at the start (apps/offset searches for them),
  * the 4-byte little-endian image size at byte 36 (read with "dd bs=4 skip=9 count=1"),
  * SHA-1 checksums of the whole image (apps/flash, MHIG path).
So a synthetic image with the same header layout exercises the same code paths.

"Patching" mimics what the real patch database shows (patches/MHIG_patch_db.csv:
header_chk_FEC_CP = header_chk_orig + 8): the image grows by 8 bytes, the size field
is updated, and a marker is appended. apps/sbin/patcher (stub) and make-profile.py
both call patch(), so their results always agree.

CLI:
  ifs.py make  <out> <size_hex_le>      create a stock image, e.g. 1C06F300
  ifs.py patch <in> <out>               write the patched image
  ifs.py header <file>                  print the size field as the unit shows it (upper-case LE hex)
"""
import hashlib
import struct
import sys

MAGIC = bytes.fromhex("EB7EFF0001000800")
PATCH_MARKER = b"SIMPATCH"


def le_hex_to_size(le_hex: str) -> int:
    return struct.unpack("<I", bytes.fromhex(le_hex))[0]


def size_to_le_hex(size: int) -> str:
    return struct.pack("<I", size).hex().upper()


def make(size: int) -> bytes:
    body = bytearray(size)
    body[0:len(MAGIC)] = MAGIC
    body[36:40] = struct.pack("<I", size)
    # deterministic, non-zero content in the first KiB so checksums are meaningful
    seed = hashlib.sha1(struct.pack("<I", size)).digest()
    for i in range(64, min(size, 1024)):
        body[i] = seed[i % len(seed)]
    return bytes(body)


def patch(stock: bytes) -> bytes:
    size = struct.unpack("<I", stock[36:40])[0]
    out = bytearray(stock[:size]) + PATCH_MARKER
    out[36:40] = struct.pack("<I", size + len(PATCH_MARKER))
    return bytes(out)


def main(argv):
    if len(argv) == 4 and argv[1] == "make":
        data = make(le_hex_to_size(argv[3]))
        open(argv[2], "wb").write(data)
    elif len(argv) == 4 and argv[1] == "patch":
        open(argv[3], "wb").write(patch(open(argv[2], "rb").read()))
    elif len(argv) == 3 and argv[1] == "header":
        with open(argv[2], "rb") as f:
            f.seek(36)
            print(f.read(4).hex().upper())
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
