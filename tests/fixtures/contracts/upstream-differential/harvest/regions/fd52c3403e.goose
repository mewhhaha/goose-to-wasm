struct Packet { id: i64, values: i64[..] }
recursive fn make(n: i64) -> Packet { return Packet { n, [n] }; }
fn replace(var route: Packet&, other: Packet&) {
    route.values = [if route.id >= 0 { route .= other; 42 } else { 43 }, 44];
}
export fn tick(n: i64) -> i64 {
    let a = Packet { n, [..4] }; a.values.push(1);
    let b = Packet { n + 10, [..5] }; b.values.push(9);
    replace(a, b); a.values = a.values[1..]; a.values.append([7, 8, 9]);
    if a.id != n || a.values.cap != 4 || a.values.len != 4 || a.values[0] != 44 || a.values[3] != 9 || b.values[0] != 9 { abort("bad limited field"); }
    return n + 1;
}
fn main() {}