struct Item { n: i64 }
const original = Item { n: 1 };
fn write(x: Item&) { x.n = 2; }
fn main() { write(original); }
