fn repeat<F>(count: i64) { for i in count { F(i); } }
fn branch<F>(choose: bool) { if choose { F(); } else { F(); } }
fn fresh() -> i64 { var total = 0; for i in 3 { let x: i64; x = i; total += x; } return total; }
fn at_break() -> i64 { let x: i64; loop { x = 9; break; } return x; }
fn after_continue() -> i64 { let x: i64; var i = 0; loop { if i == 0 { i += 1; continue; } x = 11; break; } return x; }
fn nested_break() -> i64 { let x: i64; loop { { x = 13; break; } } return x; }
fn fresh_capture() -> i64 { var total = 0; repeat(3) { i => let x: i64; x = i; total += x; }; return total; }
fn branch_capture() -> i64 { let x: i64; branch(true) { x = 17; }; return x; }
fn mutate_owner() -> i64 { let values: i64[>..] = []; repeat(3) { i => values.push(i); }; return values.len; }
fn main() { print(fresh(), " ", at_break(), " ", after_continue(), " ", nested_break(), " ", fresh_capture(), " ", branch_capture(), " ", mutate_owner()); }
