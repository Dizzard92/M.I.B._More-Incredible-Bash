# Minimal Java class-file disassembler (no JDK needed): constant pool, fields, bytecode.
# Usage: python3 -I dev/tools/re/jdis.py <file.class>...
import struct, sys

OPS = {}
_names = """nop aconst_null iconst_m1 iconst_0 iconst_1 iconst_2 iconst_3 iconst_4 iconst_5 lconst_0 lconst_1 fconst_0 fconst_1 fconst_2 dconst_0 dconst_1 bipush sipush ldc ldc_w ldc2_w iload lload fload dload aload iload_0 iload_1 iload_2 iload_3 lload_0 lload_1 lload_2 lload_3 fload_0 fload_1 fload_2 fload_3 dload_0 dload_1 dload_2 dload_3 aload_0 aload_1 aload_2 aload_3 iaload laload faload daload aaload baload caload saload istore lstore fstore dstore astore istore_0 istore_1 istore_2 istore_3 lstore_0 lstore_1 lstore_2 lstore_3 fstore_0 fstore_1 fstore_2 fstore_3 dstore_0 dstore_1 dstore_2 dstore_3 astore_0 astore_1 astore_2 astore_3 iastore lastore fastore dastore aastore bastore castore sastore pop pop2 dup dup_x1 dup_x2 dup2 dup2_x1 dup2_x2 swap iadd ladd fadd dadd isub lsub fsub dsub imul lmul fmul dmul idiv ldiv fdiv ddiv irem lrem frem drem ineg lneg fneg dneg ishl lshl ishr lshr iushr lushr iand land ior lor ixor lxor iinc i2l i2f i2d l2i l2f l2d f2i f2l f2d d2i d2l d2f i2b i2c i2s lcmp fcmpl fcmpg dcmpl dcmpg ifeq ifne iflt ifge ifgt ifle if_icmpeq if_icmpne if_icmplt if_icmpge if_icmpgt if_icmple if_acmpeq if_acmpne goto jsr ret tableswitch lookupswitch ireturn lreturn freturn dreturn areturn return getstatic putstatic getfield putfield invokevirtual invokespecial invokestatic invokeinterface invokedynamic new newarray anewarray arraylength athrow checkcast instanceof monitorenter monitorexit wide multianewarray ifnull ifnonnull goto_w jsr_w""".split()
for i, n in enumerate(_names):
    OPS[i] = n

def parse(path):
    d = open(path, 'rb').read()
    p = 8
    def u1():
        nonlocal p; v = d[p]; p += 1; return v
    def u2():
        nonlocal p; v = struct.unpack('>H', d[p:p+2])[0]; p += 2; return v
    def u4():
        nonlocal p; v = struct.unpack('>I', d[p:p+4])[0]; p += 4; return v
    n = u2(); cp = [None] * n; i = 1
    while i < n:
        t = u1()
        if t == 1:
            l = u2(); cp[i] = ('Utf8', d[p:p+l].decode('utf8', 'replace')); p += l
        elif t == 3: cp[i] = ('Int', struct.unpack('>i', d[p:p+4])[0]); p += 4
        elif t == 4: cp[i] = ('Float', struct.unpack('>f', d[p:p+4])[0]); p += 4
        elif t == 5: cp[i] = ('Long', struct.unpack('>q', d[p:p+8])[0]); p += 8; i += 1
        elif t == 6: cp[i] = ('Double', struct.unpack('>d', d[p:p+8])[0]); p += 8; i += 1
        elif t == 7: cp[i] = ('Class', u2())
        elif t == 8: cp[i] = ('String', u2())
        elif t in (9, 10, 11): cp[i] = ({9: 'Field', 10: 'Method', 11: 'IMethod'}[t], u2(), u2())
        elif t == 12: cp[i] = ('NameType', u2(), u2())
        elif t == 15: cp[i] = ('MHandle', u1(), u2())
        elif t == 16: cp[i] = ('MType', u2())
        elif t == 18: cp[i] = ('Indy', u2(), u2())
        else: raise Exception('tag %d' % t)
        i += 1

    def s(idx):
        e = cp[idx]
        if e is None: return '?'
        k = e[0]
        if k == 'Utf8': return e[1]
        if k in ('Int', 'Float', 'Long', 'Double'): return repr(e[1])
        if k == 'Class': return s(e[1])
        if k == 'String': return '"%s"' % s(e[1])
        if k in ('Field', 'Method', 'IMethod'): return '%s.%s' % (s(e[1]), s(e[2]))
        if k == 'NameType': return '%s:%s' % (s(e[1]), s(e[2]))
        return str(e)

    acc = u2(); this = u2(); sup = u2()
    print('class', s(this), 'extends', s(sup), 'flags=%x' % acc)
    ni = u2()
    print('  implements', [s(u2()) for _ in range(ni)])

    def attrs(ctx):
        nonlocal p
        na = u2(); out = []
        for _ in range(na):
            name = s(u2()); l = u4(); out.append((name, d[p:p+l])); p += l
        return out

    nf = u2()
    for _ in range(nf):
        a = u2(); nm = s(u2()); ds = s(u2()); at = attrs('f')
        cv = [struct.unpack('>H', b)[0] for n_, b in at if n_ == 'ConstantValue']
        print('  field %x %s %s %s' % (a, nm, ds, ('= ' + s(cv[0])) if cv else ''))
    nm_ = u2()
    for _ in range(nm_):
        a = u2(); nm = s(u2()); ds = s(u2()); at = attrs('m')
        print('\n  method %x %s%s' % (a, nm, ds))
        for an, b in at:
            if an != 'Code': continue
            code_len = struct.unpack('>I', b[4:8])[0]
            code = b[8:8+code_len]
            j = 0
            while j < len(code):
                op = code[j]; name = OPS.get(op, 'op%d' % op); arg = ''
                start = j; j += 1
                if name in ('bipush',): arg = str(struct.unpack('b', code[j:j+1])[0]); j += 1
                elif name == 'sipush': arg = str(struct.unpack('>h', code[j:j+2])[0]); j += 2
                elif name == 'ldc': arg = s(code[j]); j += 1
                elif name in ('ldc_w', 'ldc2_w', 'getstatic', 'putstatic', 'getfield', 'putfield', 'invokevirtual', 'invokespecial', 'invokestatic', 'new', 'anewarray', 'checkcast', 'instanceof'):
                    arg = s(struct.unpack('>H', code[j:j+2])[0]); j += 2
                elif name == 'invokeinterface': arg = s(struct.unpack('>H', code[j:j+2])[0]); j += 4
                elif name == 'invokedynamic': arg = s(struct.unpack('>H', code[j:j+2])[0]); j += 4
                elif name in ('iload', 'lload', 'fload', 'dload', 'aload', 'istore', 'lstore', 'fstore', 'dstore', 'astore', 'ret', 'newarray'): arg = str(code[j]); j += 1
                elif name == 'iinc': arg = '%d %d' % (code[j], struct.unpack('b', code[j+1:j+2])[0]); j += 2
                elif name.startswith('if') or name in ('goto', 'jsr'): arg = '-> %d' % (start + struct.unpack('>h', code[j:j+2])[0]); j += 2
                elif name == 'multianewarray': arg = s(struct.unpack('>H', code[j:j+2])[0]); j += 3
                elif name == 'tableswitch':
                    j = (j + 3) & ~3
                    df, lo, hi = struct.unpack('>iii', code[j:j+12]); j += 12
                    offs = struct.unpack('>%di' % (hi - lo + 1), code[j:j+4*(hi-lo+1)]); j += 4*(hi-lo+1)
                    arg = 'default->%d ' % (start+df) + ' '.join('%d->%d' % (lo+k, start+o) for k, o in enumerate(offs))
                elif name == 'lookupswitch':
                    j = (j + 3) & ~3
                    df, np_ = struct.unpack('>ii', code[j:j+8]); j += 8
                    pairs = [struct.unpack('>ii', code[j+8*k:j+8*k+8]) for k in range(np_)]; j += 8*np_
                    arg = 'default->%d ' % (start+df) + ' '.join('%d->%d' % (k, start+o) for k, o in pairs)
                elif name == 'wide': arg = 'WIDE'; j += 3
                print('    %4d %s %s' % (start, name, arg))

for f in sys.argv[1:]:
    parse(f)
    print('=' * 70)
