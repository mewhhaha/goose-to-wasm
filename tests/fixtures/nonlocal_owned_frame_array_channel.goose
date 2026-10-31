struct F { id: i64, values: i64[>..] }
var g = F { 9, [7, 8, 9, 10] };
fn stop() -> i64 { return 9 from canceled; }
fn canceled() -> i64 { return [11, stop()] from build; }
recursive fn quit(n: i64) -> i64 { if n > 0 { return quit(n - 1); } return 7 from find; }
fn build(flag: bool) -> i64[>..] { if flag { print(canceled()); } return [quit(1); 16]; }
fn make(flag: bool) -> F { return F { 7, build(flag) }; }
fn find(flag: bool) -> i64 { g = make(flag); 0 }
fn main() { print(find(true), " ", g.id, " ", g.values.len, " ", g.values[0]); }
