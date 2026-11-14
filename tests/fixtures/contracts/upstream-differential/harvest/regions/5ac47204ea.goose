export fn tick(n: i64) -> i64 {
    var values: i64[>..] = [if n % 2 == 0 { return n + 1; } else { n }];
    values.push(n + 1); return values[1];
}
fn main() {}