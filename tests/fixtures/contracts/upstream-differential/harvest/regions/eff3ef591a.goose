export fn tick(n: i64) -> i64 {
    var total = 0; var values: i64[>..] = [n];
    recursive fn add(k: i64) -> i64 { total += k; values.push(k); return values.len; }
    for i in 100 { add(i); }
    if total != 4950 || values.len != 101 || values[0] != n || values[100] != 99 { abort("bad static capture"); }
    return n + 1;
}
fn main() {}