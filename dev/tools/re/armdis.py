# Lists or disassembles functions of a 32-bit ARM ELF (e.g. CarPlay Maps VC core.so).
# Needs capstone and pyelftools: pip install --target dev/.tools/py capstone pyelftools
# Usage: PYTHONPATH=dev/.tools/py python3 dev/tools/re/armdis.py <elf> [function...]
import sys, struct
from elftools.elf.elffile import ELFFile
from elftools.elf.relocation import RelocationSection
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB

path = sys.argv[1]
want = sys.argv[2:]  # function names to disassemble; empty = list functions
f = open(path, 'rb'); elf = ELFFile(f); data = open(path, 'rb').read()

syms = {}
funcs = []
for sec in elf.iter_sections():
    if sec.header.sh_type in ('SHT_SYMTAB', 'SHT_DYNSYM'):
        for s in sec.iter_symbols():
            if s.name and s['st_value']:
                syms.setdefault(s['st_value'] & ~1, s.name)
                if s['st_info']['type'] == 'STT_FUNC':
                    funcs.append((s.name, s['st_value'], s['st_size']))

# relocation targets (for PLT / GOT names)
relnames = {}
for sec in elf.iter_sections():
    if isinstance(sec, RelocationSection):
        st = elf.get_section(sec['sh_link'])
        for r in sec.iter_relocations():
            if r['r_info_sym']:
                relnames[r['r_offset']] = st.get_symbol(r['r_info_sym']).name

def vaddr_to_off(va):
    for seg in elf.iter_segments():
        if seg['p_type'] == 'PT_LOAD' and seg['p_vaddr'] <= va < seg['p_vaddr'] + seg['p_filesz']:
            return va - seg['p_vaddr'] + seg['p_offset']
    return None

def cstr(va):
    o = vaddr_to_off(va)
    if o is None: return None
    e = data.find(b'\0', o)
    s = data[o:e]
    if 3 <= len(s) < 120 and all(32 <= c < 127 for c in s):
        return s.decode()
    return None

# PLT: map plt stub address -> name using got relocations
plt = {}
pltsec = elf.get_section_by_name('.plt')
if pltsec:
    md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
    base = pltsec['sh_addr']; code = pltsec.data()
    ins = list(md.disasm(code, base))
    for i in range(len(ins) - 2):
        a, b, c = ins[i], ins[i+1], ins[i+2]
        if a.mnemonic == 'add' and 'ip, pc' in a.op_str and b.mnemonic == 'add' and c.mnemonic == 'ldr' and c.op_str.startswith('pc, [ip'):
            try:
                imm1 = int(a.op_str.split('#')[1], 0); imm2 = int(b.op_str.split('#')[1], 0); imm3 = int(c.op_str.split('#')[1].rstrip(']!'), 0)
            except Exception:
                continue
            got = a.address + 8 + imm1 + imm2 + imm3
            if got in relnames: plt[a.address] = relnames[got]

if not want:
    for n, v, sz in sorted(funcs, key=lambda x: x[1]):
        print('%08x %5d %s%s' % (v & ~1, sz, n, ' (thumb)' if v & 1 else ''))
    sys.exit()

for name in want:
    for n, v, sz in funcs:
        if n != name: continue
        thumb = v & 1; addr = v & ~1
        md = Cs(CS_ARCH_ARM, CS_MODE_THUMB if thumb else CS_MODE_ARM)
        code = data[vaddr_to_off(addr):vaddr_to_off(addr) + sz]
        print('==== %s @%08x size %d' % (n, addr, sz))
        for i in md.disasm(code, addr):
            note = ''
            if i.mnemonic.startswith('ldr') and '[pc, #' in i.op_str:
                imm = int(i.op_str.split('#')[1].rstrip(']'), 0)
                lit = ((i.address + (4 if thumb else 8)) & ~3) + imm
                lo = vaddr_to_off(lit)
                if lo is not None:
                    val = struct.unpack('<I', data[lo:lo+4])[0]
                    note = '; =0x%x' % val
                    if lit in relnames: note += ' <%s>' % relnames[lit]
            if i.mnemonic in ('bl', 'blx', 'b') and i.op_str.startswith('#'):
                t = int(i.op_str[1:], 0)
                note = '; ' + (plt.get(t) or syms.get(t) or '')
            print('  %08x  %-8s %s %s' % (i.address, i.mnemonic, i.op_str, note))
