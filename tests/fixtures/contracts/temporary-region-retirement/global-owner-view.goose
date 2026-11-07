fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
var saved: i64[>..] = [7, 8, 9];
let view: const i64[:] = saved[..];
let first = make(1).len;
let second = make(2).len;
fn main() { var total: i64 = 0; for i in 0..40 { saved.append(make(i)); for value in make(1) { total += value; } } saved[0] = 70; print(view[0], " ", view[1], " ", view[2], " ", saved.len, " ", saved[122], " ", first + second, " ", total); }
