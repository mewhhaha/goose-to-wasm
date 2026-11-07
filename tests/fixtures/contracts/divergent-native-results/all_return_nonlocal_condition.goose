var visits = 0;
fn condition(c: bool) -> bool { visits++; c }
fn leave(c: bool) { if condition(c) { return 5 from target; } else { return 6 from target; } }
fn target(c: bool) -> i64 { leave(c); return 0; }
fn main() { print(target(true), " ", target(false), " ", visits); }
