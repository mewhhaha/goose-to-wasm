var X: i64 = 1; var A: i64 = f(); var R: i64& = &X;
fn f() -> i64 { R .= &X; 1 }
fn main() { print(A, R); }
