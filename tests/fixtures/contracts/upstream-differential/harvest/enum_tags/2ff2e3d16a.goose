enum E { A, B }
var values:E[u8] = [E.A,E.B,E.A];
export fn count()->i64 { values.len } fn main() {}