var visits = 0;
fn condition(c: bool) -> bool { visits++; c }
fn pick(c: bool) -> i64 { guard condition(c) else { return 4; } return 8; }
fn main() { print(pick(false), " ", pick(true), " ", visits); }
