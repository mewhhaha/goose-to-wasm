extern fn gate() -> i64;
struct Bag { values: i64[>..] }
fn make() -> Bag { print(7); return Bag { values: [42] }; }
fn main() { make(); }
