var neighbor: i64[>..] = [987654321];
fn transform(values: i64[>..]) -> i64[>..] { values.push(9); return values; }
fn consume(values: i64[>..]) -> i64 { return values[0] + 1; }
export fn tick(n: i64) -> i64 {
    let result = transform([if n % 2 == 0 { return n + 1; } else { n }]);
    return consume(copy(result));
}
fn main() { print(consume([1]) + consume([2]) + consume([3])); }