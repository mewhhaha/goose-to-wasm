struct Item { n: varint }
fn read(x: const varint&) -> i64 { x }
fn main() { let value = Item { n: 300 }; print(read(value.n)); }
