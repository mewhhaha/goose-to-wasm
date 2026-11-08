fn choose(x: bool) -> bool { var y: bool = x; y = !y; return y; }
fn main() { print(choose(false)); print(choose(true)); }
