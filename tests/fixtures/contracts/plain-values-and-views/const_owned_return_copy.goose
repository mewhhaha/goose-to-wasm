struct Item { n: i64 }
const original = Item { n: 1 };
fn value() -> const Item { original }
fn main() { var copied = value(); copied.n = 3; print(copied.n, " ", original.n); }
