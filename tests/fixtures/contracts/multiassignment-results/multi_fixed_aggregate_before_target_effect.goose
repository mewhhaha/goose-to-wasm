struct Item { n: i64 }
fn pair(a: Item&) -> Item&, i64 { return a, 4; }
fn change(a: Item&) -> i64 { a.n = 9; 0 }
fn main() { var a = Item { n: 3 }; var xs = [Item { n: 0 }]; var out = 0; xs[change(a)], out = pair(a); print(xs[0].n, " ", out, " ", a.n); }
