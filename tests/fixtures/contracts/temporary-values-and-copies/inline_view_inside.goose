struct Owned { bytes: i64[2] }
fn make() -> Owned[2] { [Owned { bytes: [1, 2] }, Owned { bytes: [3, 4] }] }
fn main() { var total: i64 = 0; for &value in make() { let view: const i64[:] = value.bytes[..]; total += view[0]; } print(total); }
