struct Item { n: i64 }
const original = [Item { n: 1 }];
fn main() { var copied = original[0]; copied.n = 2; print(copied.n, " ", original[0].n); }
