extern fn bench_input() -> i64;
struct Pair { x: i64, y: i64 }
struct Inner { code: u8, values: Pair[>..] }
struct Middle { id: i64, inner: Inner }
struct Outer { tag: u16, middle: Middle }
struct Leaf { id: i64, values: i64[] }
struct Variable { tag: u8, leaf: Leaf }
struct LimitedLeaf { id: i64, values: i64[..] }
struct Limited { tag: u8, leaf: LimitedLeaf }
var global = Outer { 9, Middle { 10, Inner { 11, [Pair { 12, 13 }] } } };
fn make(n: i64) -> Outer { return Outer { 1, Middle { n, Inner { 2, [Pair { n + 1, n + 2 }] } } }; }
fn bump(p: Outer&) -> i64 {
    p.tag += 1; p.middle.id += 10; p.middle.inner.code += 2;
    p.middle.inner.values[0].x += 20; p.middle.inner.values.push(Pair { 30, 31 }); return p.middle.id;
}
fn aliases(n: i64) -> Outer, i64, Outer { var local = make(n); return local, bump(local), local; }
fn changed(p: Outer) -> Outer { p.middle.id += 100; p.middle.inner.values[0].x += 200; return p; }
fn borrowed(p: const Outer&) -> const Middle& { return p.middle; }
recursive fn forward(n: i64) -> Outer { if n <= 0 { return make(7); } return forward(n - 1); }
fn interrupted(n: i64) -> i64 {
    global = Outer { 3, Middle { if n > 0 { return 77; } else { 4 }, Inner { 5, [Pair { 6, 7 }] } } };
    return 0;
}
fn var_bump(p: Variable&) -> i64 { p.tag += 1; p.leaf.id += 10; p.leaf.values[0] += 20; return p.leaf.id; }
fn variable(n: i64) -> Variable, i64, Variable {
    var p = Variable { 1, Leaf { n, [n + 1] } }; return p, var_bump(p), p;
}
fn main() {
    let n = bench_input(); let original = make(n); let copied = changed(copy(original));
    let kept: const Middle& = borrowed(original);
    print(kept.id, " ", original.middle.inner.values[0].x, " ", copied.middle.id, " ", copied.middle.inner.values[0].x);
    let a, marker, b = aliases(n);
    print(a.tag, " ", a.middle.id, " ", a.middle.inner.code, " ", a.middle.inner.values.len, " ", a.middle.inner.values[0].x,
          " ", marker, " ", b.tag, " ", b.middle.id, " ", b.middle.inner.code, " ", b.middle.inner.values.len);
    let chosen: Outer = if n > 0 { make(40) } else { make(50) };
    let looped: Outer = loop { var p = make(60); break copy(p); };
    print(chosen.middle.id, " ", looped.middle.id, " ", forward(20).middle.id, " ", kept.id);
    let exit = interrupted(n); print(exit, " ", global.tag, " ", global.middle.id, " ", global.middle.inner.code, " ", global.middle.inner.values[0].x);
    let va, vm, vb = variable(n); print(va.tag, " ", va.leaf.id, " ", va.leaf.values, " ", vm, " ", vb.tag, " ", vb.leaf.id, " ", vb.leaf.values);
    var limit = Limited { 1, LimitedLeaf { n, [..4] } }; limit.leaf.values.push(n);
    let independent = copy(limit); limit.leaf.values = limit.leaf.values[..]; limit.leaf.values.push(99);
    print(limit.leaf.values, " ", limit.leaf.values.cap, " ", independent.leaf.values, " ", independent.leaf.values.cap);
}
