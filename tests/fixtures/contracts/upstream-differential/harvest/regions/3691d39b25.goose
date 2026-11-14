struct Packet { id: i64, values: i64[>..] }
fn replace(var route: Packet&, other: Packet&) {
    route = Packet { if true { route .= other; 42 } else { 43 }, [44, 45] };
}
recursive fn make(n: i64) -> Packet { return Packet { n, [n, n + 1] }; }
export fn tick(n: i64) -> i64 {
    var a = make(n); var b = make(n + 10); replace(a, b);
    if a.id != 42 || a.values.len != 2 || a.values[0] != 44 || b.id != n + 10 || b.values[0] != n + 10 { abort("bad pinned frame"); }
    for i in 100 { if make(i).values[1] != i + 1 { abort("bad frame temporary"); } }
    return n + 1;
}
fn main() {}