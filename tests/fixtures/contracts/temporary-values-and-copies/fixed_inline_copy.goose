var g: i64[2] = [1, 2];
var h: i64[2] = [3, 4];
var effects: i64 = 0;
fn reset() { g = [1, 2]; h = [3, 4]; }
fn change() -> i64 { effects += 1; g = [8, 9]; 0 }
fn head(xs: const i64[:], ignored: i64) -> i64 { xs[0] }
struct Holder { values: i64[2] }
var holder = Holder { values: [1, 2] };
fn get() -> i64[2] { g }
fn again() -> i64[2] { get() }
fn get_holder() -> Holder { holder }
fn change_holder() -> i64 { holder.values = [8, 9]; 0 }
fn bytes(xs: const u8[:], ignored: i64) -> i64 { xs[0] as i64 }
fn main() { print(head(get()[..], change())); reset(); print(head(again()[..], change())); reset(); print(get()[change()]); reset(); print(head(get_holder().values[..], change_holder())); print(bytes(bytes_of(get()), change())); }
