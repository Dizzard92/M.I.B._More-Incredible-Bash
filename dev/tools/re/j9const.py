# Needs numpy (PYTHONPATH=dev/.tools/py after pip install --target dev/.tools/py numpy).
# Usage: python3 dev/tools/re/j9const.py <lsd.jxe> '<regex for constant names>'
# Find static final int constants in a J9 ROM image (lsd.jxe) by locating
# J9ROMFieldShape records: {SRP name, SRP signature, U32 modifiers, U32 value}.
import sys, re, struct
import numpy as np

path = sys.argv[1]
pattern = re.compile(sys.argv[2].encode())
data = open(path, 'rb').read()
arr = np.frombuffer(data[:len(data) // 4 * 4], dtype='<i4')
pos = np.arange(len(arr), dtype=np.int64) * 4
targets = pos + arr.astype(np.int64)

# candidate J9UTF8 records: u16 length followed by the name, length matching
names = {}
for m in re.finditer(rb'[A-Za-z_][A-Za-z0-9_$]{2,80}', data):
    s = m.group(0)
    if not pattern.fullmatch(s):
        continue
    o = m.start() - 2
    if o >= 0 and struct.unpack('<H', data[o:o+2])[0] == len(s):
        names.setdefault(s.decode(), []).append(o)

sig_I = set()
for m in re.finditer(rb'\x01\x00I', data):
    sig_I.add(m.start())

def utf8_at(o):
    if o < 0 or o + 2 > len(data): return None
    l = struct.unpack('<H', data[o:o+2])[0]
    return data[o+2:o+2+l]

for name, offs in sorted(names.items()):
    found = []
    for o in offs:
        hits = np.nonzero(targets == o)[0]
        for h in hits:
            p = int(h) * 4
            sig = utf8_at(p + 4 + struct.unpack('<i', data[p+4:p+8])[0])
            if sig is None or len(sig) > 40: continue
            mods = struct.unpack('<I', data[p+8:p+12])[0]
            val = struct.unpack('<i', data[p+12:p+16])[0]
            found.append((p, sig.decode('latin1'), mods, val))
    for p, sig, mods, val in found:
        if sig == 'I':
            print('%-34s = %6d   (sig %s mods 0x%x @0x%x)' % (name, val, sig, mods, p))
    if not any(f[1] == 'I' for f in found):
        print('%-34s   (no int field shape found; %d refs)' % (name, len(found)))
