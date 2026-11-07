struct Item { n: i64 }
const original = Item { n: 1 };
var copied = original;
fn main() { copied.n = 2; print(copied.n, " ", original.n); }
