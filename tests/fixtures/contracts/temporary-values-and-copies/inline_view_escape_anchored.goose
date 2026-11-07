struct Owned { bytes: i64[2] }
var anchor: i64[2] = [0, 0];
fn make() -> Owned[2] { [Owned { bytes: [1, 2] }, Owned { bytes: [3, 4] }] }
fn main() { var out: const i64[:] = anchor[..]; for &value in make() { out = value.bytes[..]; } print(out.len); }
