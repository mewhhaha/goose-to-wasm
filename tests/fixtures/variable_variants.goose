extern fn bench_input() -> i64;
enum Payload<T> {
    Small { value: T },
    Data { tag: u8, id: i64, values: T[] },
    Limited { id: i64, values: T[..] },
    Growing { values: T[>..] },
}
enum Tree { Leaf { values: i64[] }, Branch { id: i64, leaf: Tree.Leaf } }
struct Wrapper { id: i64, data: Payload<i64>.Data }
var empty: Payload<i64>.Data;
fn make(n: i64) -> Payload<i64>.Data { return Payload<i64>.Data { 1, n, [n + 1, n + 2] }; }
fn bump(p: Payload<i64>.Data&) -> i64 { p.id += 10; p.values[0] += 20; return p.id; }
fn aliases(n: i64) -> Payload<i64>.Data, i64, Payload<i64>.Data {
    var p = make(n); return p, bump(p), p;
}
fn changed(p: Payload<i64>.Data) -> Payload<i64>.Data { p.id += 100; p.values[0] += 200; return p; }
inline fn relay(n: i64) -> Payload<i64>.Data { var p = make(n); return p; }
recursive fn forward(n: i64) -> Payload<i64>.Data { if n <= 0 { return make(7); } return forward(n - 1); }
fn first(p: const Payload<i64>.Data&) -> const i64& { return p.id; }
fn early(n: i64) -> Payload<i64>.Data {
    return Payload<i64>.Data { 1, if n > 0 { return make(80); } else { 2 }, [3, 4] };
}
fn main() {
    let n = bench_input(); let original = make(n); let independent = changed(copy(original));
    let kept: const i64& = first(original);
    print(empty.tag, " ", empty.id, " ", empty.values.len);
    print(original.id, " ", original.values, " ", independent.id, " ", independent.values);
    let a, marker, b = aliases(n); print(a.id, " ", a.values, " ", marker, " ", b.id, " ", b.values);
    let chosen: Payload<i64>.Data = if n > 0 { make(30) } else { make(40) };
    let looped: Payload<i64>.Data = loop { var local = make(50); break copy(local); };
    let exited = early(n); print(chosen.id, " ", looped.id, " ", exited.id, " ", forward(20).id, " ", kept);
    let wrapped = Wrapper { n, make(n + 60) }; let copied = copy(wrapped); copied.data.values[0] += 100;
    print(wrapped.id, " ", wrapped.data.id, " ", wrapped.data.values, " ", copied.data.values);
    let branch = Tree.Branch { n, Tree.Leaf { [n + 70, n + 71] } }; let separate = copy(branch); separate.leaf.values[0] += 200;
    print(branch.id, " ", branch.leaf.values, " ", separate.leaf.values);
    let limited = Payload<i64>.Limited { n, [..4] }; limited.values.push(n);
    let saved = copy(limited); limited.values = limited.values[..]; limited.values.push(99);
    print(limited.id, " ", limited.values, " ", limited.values.cap, " ", saved.values, " ", saved.values.cap);
}
