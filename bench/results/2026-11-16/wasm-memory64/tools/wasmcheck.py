#!/usr/bin/env python3
"""wasmcheck.py module.wasm [--max N] [--show NAME_OR_INDEX]: type-check every function body of a module
(32- or 64-bit memory) and print the first error of each function with a few instructions of context.
Covers what the direct backend emits: MVP, sign extension, saturating truncation, bulk memory, and the
SIMD instructions listed in SIMD below. Not a full validator."""
import sys, collections

I32, I64, F32, F64, V128 = 'i32', 'i64', 'f32', 'f64', 'v128'
VT = {0x7f: I32, 0x7e: I64, 0x7d: F32, 0x7c: F64, 0x7b: V128}

class Reader:
    def __init__(self, b, i=0, end=None): self.b = b; self.i = i; self.end = len(b) if end is None else end
    def byte(self): v = self.b[self.i]; self.i += 1; return v
    def u(self):
        r = 0; s = 0
        while True:
            c = self.byte(); r |= (c & 0x7f) << s; s += 7
            if c < 0x80: return r
    def s(self, bits=64):
        r = 0; s = 0
        while True:
            c = self.byte(); r |= (c & 0x7f) << s; s += 7
            if c < 0x80:
                if c & 0x40: r -= 1 << s
                return r
    def name(self): n = self.u(); v = self.b[self.i:self.i + n].decode('utf8', 'replace'); self.i += n; return v

NUM = {}
def num(op, name, ins, outs): NUM[op] = (name, ins, outs)
for op, n in zip(range(0x46, 0x50), ['eq', 'ne', 'lt_s', 'lt_u', 'gt_s', 'gt_u', 'le_s', 'le_u', 'ge_s', 'ge_u']):
    num(op, 'i32.' + n, [I32, I32], [I32]); num(op + 0x0b, 'i64.' + n, [I64, I64], [I32])
num(0x45, 'i32.eqz', [I32], [I32]); num(0x50, 'i64.eqz', [I64], [I32])
for op, n in zip(range(0x5b, 0x61), ['eq', 'ne', 'lt', 'gt', 'le', 'ge']):
    num(op, 'f32.' + n, [F32, F32], [I32]); num(op + 6, 'f64.' + n, [F64, F64], [I32])
for op, n in zip(range(0x67, 0x6a), ['clz', 'ctz', 'popcnt']):
    num(op, 'i32.' + n, [I32], [I32]); num(op + 0x12, 'i64.' + n, [I64], [I64])
for op, n in zip(range(0x6a, 0x79), ['add', 'sub', 'mul', 'div_s', 'div_u', 'rem_s', 'rem_u', 'and', 'or', 'xor', 'shl', 'shr_s', 'shr_u', 'rotl', 'rotr']):
    num(op, 'i32.' + n, [I32, I32], [I32]); num(op + 0x12, 'i64.' + n, [I64, I64], [I64])
for op, n in zip(range(0x8b, 0x92), ['abs', 'neg', 'ceil', 'floor', 'trunc', 'nearest', 'sqrt']):
    num(op, 'f32.' + n, [F32], [F32]); num(op + 0x0e, 'f64.' + n, [F64], [F64])
for op, n in zip(range(0x92, 0x99), ['add', 'sub', 'mul', 'div', 'min', 'max', 'copysign']):
    num(op, 'f32.' + n, [F32, F32], [F32]); num(op + 0x0e, 'f64.' + n, [F64, F64], [F64])
CONV = {0xa7: ('i32.wrap_i64', I64, I32), 0xa8: ('i32.trunc_f32_s', F32, I32), 0xa9: ('i32.trunc_f32_u', F32, I32),
        0xaa: ('i32.trunc_f64_s', F64, I32), 0xab: ('i32.trunc_f64_u', F64, I32), 0xac: ('i64.extend_i32_s', I32, I64),
        0xad: ('i64.extend_i32_u', I32, I64), 0xae: ('i64.trunc_f32_s', F32, I64), 0xaf: ('i64.trunc_f32_u', F32, I64),
        0xb0: ('i64.trunc_f64_s', F64, I64), 0xb1: ('i64.trunc_f64_u', F64, I64), 0xb2: ('f32.convert_i32_s', I32, F32),
        0xb3: ('f32.convert_i32_u', I32, F32), 0xb4: ('f32.convert_i64_s', I64, F32), 0xb5: ('f32.convert_i64_u', I64, F32),
        0xb6: ('f32.demote_f64', F64, F32), 0xb7: ('f64.convert_i32_s', I32, F64), 0xb8: ('f64.convert_i32_u', I32, F64),
        0xb9: ('f64.convert_i64_s', I64, F64), 0xba: ('f64.convert_i64_u', I64, F64), 0xbb: ('f64.promote_f32', F32, F64),
        0xbc: ('i32.reinterpret_f32', F32, I32), 0xbd: ('i64.reinterpret_f64', F64, I64), 0xbe: ('f32.reinterpret_i32', I32, F32),
        0xbf: ('f64.reinterpret_i64', I64, F64), 0xc0: ('i32.extend8_s', I32, I32), 0xc1: ('i32.extend16_s', I32, I32),
        0xc2: ('i64.extend8_s', I64, I64), 0xc3: ('i64.extend16_s', I64, I64), 0xc4: ('i64.extend32_s', I64, I64)}
for op, (n, a, r) in CONV.items(): num(op, n, [a], [r])
LOAD = {0x28: ('i32.load', I32), 0x29: ('i64.load', I64), 0x2a: ('f32.load', F32), 0x2b: ('f64.load', F64), 0x2c: ('i32.load8_s', I32),
        0x2d: ('i32.load8_u', I32), 0x2e: ('i32.load16_s', I32), 0x2f: ('i32.load16_u', I32), 0x30: ('i64.load8_s', I64),
        0x31: ('i64.load8_u', I64), 0x32: ('i64.load16_s', I64), 0x33: ('i64.load16_u', I64), 0x34: ('i64.load32_s', I64), 0x35: ('i64.load32_u', I64)}
STORE = {0x36: ('i32.store', I32), 0x37: ('i64.store', I64), 0x38: ('f32.store', F32), 0x39: ('f64.store', F64), 0x3a: ('i32.store8', I32),
         0x3b: ('i32.store16', I32), 0x3c: ('i64.store8', I64), 0x3d: ('i64.store16', I64), 0x3e: ('i64.store32', I64)}
# SIMD: sub-opcode -> (name, immediate kind, ins, outs). 'mem' memarg, 'lane' one byte, 'c16' sixteen bytes, None none.
SIMD = {0x00: ('v128.load', 'mem', ['A'], [V128]), 0x0b: ('v128.store', 'mem', ['A', V128], []), 0x0c: ('v128.const', 'c16', [], [V128]),
        0x0d: ('i8x16.shuffle', 'c16', [V128, V128], [V128]), 0x0e: ('i8x16.swizzle', None, [V128, V128], [V128]),
        0x0f: ('i8x16.splat', None, [I32], [V128]), 0x10: ('i16x8.splat', None, [I32], [V128]), 0x11: ('i32x4.splat', None, [I32], [V128]),
        0x12: ('i64x2.splat', None, [I64], [V128]), 0x15: ('i8x16.extract_lane_s', 'lane', [V128], [I32]), 0x16: ('i8x16.extract_lane_u', 'lane', [V128], [I32]),
        0x17: ('i8x16.replace_lane', 'lane', [V128, I32], [V128]), 0x1b: ('i32x4.extract_lane', 'lane', [V128], [I32]),
        0x1c: ('i32x4.replace_lane', 'lane', [V128, I32], [V128]), 0x1d: ('i64x2.extract_lane', 'lane', [V128], [I64]),
        0x1e: ('i64x2.replace_lane', 'lane', [V128, I64], [V128]), 0x53: ('v128.any_true', None, [V128], [I32]),
        0x63: ('i8x16.all_true', None, [V128], [I32]), 0x64: ('i8x16.bitmask', None, [V128], [I32])}
for op in range(0x23, 0x4d): SIMD.setdefault(op, ('simd.compare', None, [V128, V128], [V128]))
for op in (0x4d,): SIMD[op] = ('v128.not', None, [V128], [V128])
for op in (0x4e, 0x4f, 0x50, 0x51): SIMD[op] = ('v128.bitop', None, [V128, V128], [V128])
SIMD[0x52] = ('v128.bitselect', None, [V128, V128, V128], [V128])
for op in (0x6e, 0x71, 0x8e, 0x91, 0xae, 0xb1, 0xce, 0xd1, 0x76, 0x77, 0x78, 0x79): SIMD.setdefault(op, ('simd.binary', None, [V128, V128], [V128]))

class Err(Exception): pass

def check(module, func):
    types, ftypes, globals_, addr, names = module['types'], module['ftypes'], module['globals'], module['addr'], module['names']
    params, results = types[ftypes[func['index']]]
    locals_ = list(params) + func['locals']
    r = Reader(module['bytes'], func['start'], func['end'])
    stack = []; ctrl = [dict(kind='func', start=0, res=list(results), unreachable=False, label=list(results))]
    trail = collections.deque(maxlen=12)
    def push(t): stack.append(t)
    def pop(want=None):
        c = ctrl[-1]
        if len(stack) == c['start']:
            if c['unreachable']: return want or '?'
            raise Err(f'stack empty, wanted {want}')
        t = stack.pop()
        if want and t != want and t != '?' and want != '?': raise Err(f'wanted {want}, got {t}')
        return t
    def pops(ws):
        for w in reversed(ws): pop(addr if w == 'A' else w)
    def unreachable(): c = ctrl[-1]; del stack[c['start']:]; c['unreachable'] = True
    def blocktype():
        b = r.b[r.i]
        if b == 0x40: r.i += 1; return [], []
        if b in VT: r.i += 1; return [], [VT[b]]
        return types[r.s()]
    def label(depth):
        if depth >= len(ctrl): raise Err('bad label')
        return ctrl[-1 - depth]['label']
    try:
        while r.i < r.end:
            at = r.i; op = r.byte(); text = hex(op)
            if op == 0x00: text = 'unreachable'; unreachable()
            elif op == 0x01: text = 'nop'
            elif op in (0x02, 0x03, 0x04):
                ins, outs = blocktype()
                if op == 0x04: pop(I32)
                pops(ins)
                ctrl.append(dict(kind={2: 'block', 3: 'loop', 4: 'if'}[op], start=len(stack), res=list(outs), unreachable=False,
                                 label=list(ins) if op == 0x03 else list(outs), ins=list(ins)))
                for t in ins: push(t)
                text = {2: 'block', 3: 'loop', 4: 'if'}[op]
            elif op == 0x05:
                c = ctrl[-1]; pops(c['res'])
                if len(stack) != c['start']: raise Err('values left before else')
                c['unreachable'] = False; c['kind'] = 'else'
                for t in c.get('ins', []): push(t)
                text = 'else'
            elif op == 0x0b:
                c = ctrl[-1]; pops(c['res'])
                if len(stack) != c['start']: raise Err(f'{len(stack) - c["start"]} values left at end: {stack[c["start"]:]}')
                ctrl.pop()
                for t in c['res']: push(t)
                text = 'end'
                if not ctrl: break
            elif op == 0x0c: d = r.u(); pops(label(d)); unreachable(); text = f'br {d}'
            elif op == 0x0d:
                d = r.u(); pop(I32); l = label(d); pops(l)
                for t in l: push(t)
                text = f'br_if {d}'
            elif op == 0x0e:
                n = r.u(); ds = [r.u() for _ in range(n + 1)]; pop(I32); pops(label(ds[-1])); unreachable(); text = 'br_table'
            elif op == 0x0f: pops(results); unreachable(); text = 'return'
            elif op == 0x10:
                f = r.u(); ins, outs = types[ftypes[f]]; text = f'call {f} {names.get(f, "")} {ins}->{outs}'
                pops(ins)
                for t in outs: push(t)
            elif op == 0x11:
                ti = r.u(); r.u(); ins, outs = types[ti]; text = f'call_indirect {ins}->{outs}'; pop(I32); pops(ins)
                for t in outs: push(t)
            elif op == 0x1a: pop(); text = 'drop'
            elif op == 0x1b:
                pop(I32); a = pop(); b = pop(a if a != '?' else None); push(a if a != '?' else b); text = 'select'
            elif op == 0x20: i = r.u(); text = f'local.get {i} ({locals_[i]})'; push(locals_[i])
            elif op == 0x21: i = r.u(); text = f'local.set {i} ({locals_[i]})'; pop(locals_[i])
            elif op == 0x22: i = r.u(); text = f'local.tee {i} ({locals_[i]})'; pop(locals_[i]); push(locals_[i])
            elif op == 0x23: i = r.u(); text = f'global.get {i} ({globals_[i]})'; push(globals_[i])
            elif op == 0x24: i = r.u(); text = f'global.set {i} ({globals_[i]})'; pop(globals_[i])
            elif op in LOAD: r.u(); off = r.u(); n, t = LOAD[op]; text = f'{n} +{off}'; pop(addr); push(t)
            elif op in STORE: r.u(); off = r.u(); n, t = STORE[op]; text = f'{n} +{off}'; pop(t); pop(addr)
            elif op == 0x3f: r.u(); push(addr); text = 'memory.size'
            elif op == 0x40: r.u(); pop(addr); push(addr); text = 'memory.grow'
            elif op == 0x41: v = r.s(); push(I32); text = f'i32.const {v}'
            elif op == 0x42: v = r.s(); push(I64); text = f'i64.const {v}'
            elif op == 0x43: r.i += 4; push(F32); text = 'f32.const'
            elif op == 0x44: r.i += 8; push(F64); text = 'f64.const'
            elif op in NUM:
                n, ins, outs = NUM[op]; text = n; pops(ins)
                for t in outs: push(t)
            elif op == 0xfc:
                sub = r.u()
                if sub <= 7:
                    src = [F32, F32, F64, F64, F32, F32, F64, F64][sub]; dst = I32 if sub < 4 else I64; pop(src); push(dst); text = f'trunc_sat {sub}'
                elif sub == 10: r.u(); r.u(); pop(addr); pop(addr); pop(addr); text = 'memory.copy'
                elif sub == 11: r.u(); pop(addr); pop(I32); pop(addr); text = 'memory.fill'
                else: raise Err(f'unknown 0xfc {sub}')
            elif op == 0xfd:
                sub = r.u()
                if sub not in SIMD: raise Err(f'unknown simd {hex(sub)}')
                n, imm, ins, outs = SIMD[sub]; text = n
                if imm == 'mem': r.u(); off = r.u(); text += f' +{off}'
                elif imm == 'lane': text += f' {r.byte()}'
                elif imm == 'c16': r.i += 16
                pops(ins)
                for t in outs: push(t)
            else: raise Err(f'unknown opcode {hex(op)}')
            trail.append((at - func['start'], text, list(stack[-4:])))
    except Err as e:
        return str(e), at - func['start'], list(trail), text
    except IndexError:
        return 'index out of range (bad local, type or function index)', at - func['start'], list(trail), text
    return None

def parse(b):
    assert b[:4] == b'\0asm', 'not a wasm module'
    m = dict(bytes=b, types=[], ftypes=[], globals=[], addr=I32, names={}, funcs=[], imports=0, exports={})
    r = Reader(b, 8)
    while r.i < len(b):
        sid = r.byte(); size = r.u(); end = r.i + size
        if sid == 1:
            for _ in range(r.u()):
                assert r.byte() == 0x60
                ps = [VT[r.byte()] for _ in range(r.u())]; rs = [VT[r.byte()] for _ in range(r.u())]; m['types'].append((ps, rs))
        elif sid == 2:
            for _ in range(r.u()):
                mod = r.name(); name = r.name(); kind = r.byte()
                if kind == 0: m['names'][len(m['ftypes'])] = mod + '.' + name; m['ftypes'].append(r.u()); m['imports'] += 1
                elif kind == 2:
                    flags = r.byte(); r.u()
                    if flags & 1: r.u()
                    if flags & 4: m['addr'] = I64
                elif kind == 3: m['globals'].append(VT[r.byte()]); r.byte()
                else: raise SystemExit('table import not handled')
        elif sid == 3:
            for _ in range(r.u()): m['ftypes'].append(r.u())
        elif sid == 5:
            for _ in range(r.u()):
                flags = r.byte(); r.u()
                if flags & 1: r.u()
                if flags & 4: m['addr'] = I64
        elif sid == 6:
            for _ in range(r.u()):
                t = VT[r.byte()]; r.byte(); m['globals'].append(t)
                op = r.byte()
                if op == 0x41 or op == 0x42: r.s()
                elif op == 0x43: r.i += 4
                elif op == 0x44: r.i += 8
                elif op == 0x23: r.u()
                elif op == 0xfd: r.u(); r.i += 16
                assert r.byte() == 0x0b
        elif sid == 7:
            for _ in range(r.u()):
                name = r.name(); kind = r.byte(); index = r.u()
                if kind == 0: m['exports'][index] = name
        elif sid == 10:
            for k in range(r.u()):
                size2 = r.u(); body_end = r.i + size2; locals_ = []
                for _ in range(r.u()):
                    n = r.u(); t = VT[r.byte()]; locals_ += [t] * n
                m['funcs'].append(dict(index=m['imports'] + k, start=r.i, end=body_end, locals=locals_)); r.i = body_end
        elif sid == 0:
            sec = r.name()
            if sec == 'name':
                while r.i < end:
                    sub = r.byte(); sub_size = r.u(); sub_end = r.i + sub_size
                    if sub == 1:
                        for _ in range(r.u()): i = r.u(); m['names'][i] = r.name()
                    r.i = sub_end
        r.i = end
    for i, n in m['exports'].items(): m['names'].setdefault(i, n)
    return m

def main():
    args = sys.argv[1:]; limit = 40; show = None
    if '--max' in args: k = args.index('--max'); limit = int(args[k + 1]); del args[k:k + 2]
    if '--show' in args: k = args.index('--show'); show = args[k + 1]; del args[k:k + 2]
    m = parse(open(args[0], 'rb').read())
    bad = 0
    for f in m['funcs']:
        name = m['names'].get(f['index'], f'func[{f["index"]}]')
        if show is not None and show not in (name, str(f['index'])): continue
        e = check(m, f)
        if e:
            bad += 1
            if bad <= limit:
                msg, off, trail, text = e
                print(f'ERROR {name} (func {f["index"]}) +{off} at `{text}`: {msg}')
                for o, t, s in trail[-8:]: print(f'      +{o:<6} {t:<44} {s}')
    print(f'{len(m["funcs"])} functions, {bad} with errors, address type {m["addr"]}, {len(m["types"])} types, {m["imports"]} imports')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
