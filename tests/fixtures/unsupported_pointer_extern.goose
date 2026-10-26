extern fn inspect(values: const i64[:]) -> i64;
fn main() { print(inspect([1, 2, 3])); }
