var neighbor: i64[>..] = [987654321];
fn grow(values: i64[>..]&) -> i64 { values[0] += 10; values.push(99); return values.len; }
fn make(n: i64) -> i64[>..], i64, i64[>..] {
    var values: i64[>..] = [n]; return values, grow(values), values;
}
export fn tick(n: i64) -> i64 {
    let first, length, second = make(n);
    if first.len != 1 || second.len != 2 || length != 2 || first[0] != n + 10 || second[1] != 99 { abort("bad result"); }
    return first[0] - 9;
}
fn main() {}