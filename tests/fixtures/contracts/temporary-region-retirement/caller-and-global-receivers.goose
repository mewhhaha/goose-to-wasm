fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
var saved: i64[>..] = [];
fn add(out: i64[>..]&, value: i64) { out.append(make(value)); }
fn main() { var local: i64[>..] = []; for i in 0..40 { add(local, i); saved.append(make(100 + i)); for ignored in make(1) {} } var a: i64 = 0; var b: i64 = 0; for value in local { a += value; } for value in saved { b += value; } print(local.len, " ", a, " ", saved.len, " ", b); }
