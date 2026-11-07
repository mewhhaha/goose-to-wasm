fn search<F>() -> i64 { F(0); return -1; }
recursive fn visit(n: i64) -> i64 { if n < 6 { visit(n + 1); } if n == 3 { return n from search; } return 0; }
fn twice<F>() -> i64 { let a = search(F); let b = search(F); return a + b; }
fn main() { print(twice() { x => visit(x) }); }
