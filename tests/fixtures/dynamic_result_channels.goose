extern fn bench_input() -> i64;
fn make(n: i64) -> i64, i64[>..], i64[2], i64[>..<] {
    return n, [n + 1], [n + 2, n + 3], [n + 4, n + 5];
}
fn bump(values: i64[>..]&) -> i64 { values[0] += 10; return values[0]; }
fn snapshots(n: i64) -> i64[>..], i64, i64[>..] {
    var values: i64[>..] = [n];
    return values, bump(values), values;
}
fn grow(values: i64[>..]&) -> i64 { values[0] += 10; values.push(99); return values.len; }
fn growth(n: i64) -> i64[>..], i64, i64[>..] {
    var values: i64[>..] = [n]; return values, grow(values), values;
}
fn different(n: i64) -> i64[>..], i64[>..] {
    var a: i64[>..] = [n]; var b: i64[>..] = [n + 1];
    if n > 0 { return a, b; } return b, a;
}
fn copied(values: i64[>..]) -> i64[>..], i64, i64[>..] { return values, grow(values), values; }
fn interrupted(n: i64) -> i64[>..], i64, i64[>..] {
    return [1, if n > 0 { return [7], 8, [9]; } else { 2 }], 3, [4];
}
recursive fn forward(n: i64) -> i64[>..], i64, i64[>..] {
    if n <= 0 { return [20], 30, [40]; }
    return forward(n - 1);
}
fn main() {
    let n = bench_input();
    let scalar, first, fixed, second = make(n);
    second.pop(); first.push(99);
    print(scalar, " ", first, " ", fixed, " ", second);
    let before, changed, after = snapshots(n); print(before, " ", changed, " ", after);
    let old, length, extended = growth(n); print(old, " ", length, " ", extended);
    let a, b = different(n); print(a, " ", b);
    let initial, count, final = copied([n]); print(initial, " ", count, " ", final);
    let ix, iy, iz = interrupted(n); print(ix, " ", iy, " ", iz);
    let x, y, z = forward(20); print(x, " ", y, " ", z);
}
