const original = [1, 2];
fn main() { let view: const i64[:] = original; view[0] = 9; }
