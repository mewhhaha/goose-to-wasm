fn transform(values: i64[>..]) -> i64[>..] { values.push(9); return values; }
export fn tick(n: i64) -> i64 {
    let result = transform(transform([n])); return result[0] + 1;
}
fn main() {}