struct View { values: const i64[:] }
fn make(source: const i64[:]) -> View[2] { [View { values: source }, View { values: source }] }
fn pass(source: const i64[:]) -> const i64[:] { var keep: const i64[:] = source; for value in make(source) { keep = value.values; } keep }
fn main() { var source: i64[2] = [8, 9]; let result = pass(source); source[0] = 10; print(result[0], " ", result[1]); }
