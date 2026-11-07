struct View { values: const i64[:] }
fn make(source: const i64[:]) -> View[2] { [View { values: source }, View { values: source }] }
fn bad() -> const i64[:] { var source: i64[2] = [8, 9]; for value in make(source) { return value.values; } [] }
fn main() { print(bad().len); }
