struct Item { n: i64 }
const original = Item { n: 1 };
fn pick(x: Item) -> i64 { 1 }
fn pick<T>(x: T) -> i64 { 2 }
fn main() { print(pick(original)); }
