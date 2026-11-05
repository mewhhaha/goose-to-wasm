namespace init_trace;
var log: i64 = 0;
fn mark(n: i64) -> i64 { log = log * 10 + n; n }
