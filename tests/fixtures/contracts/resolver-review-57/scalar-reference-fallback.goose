import std;
fn bump(value: i64&) { value += 1; }
fn main() { var value: i64 = 41; bump(value); print(value); }
