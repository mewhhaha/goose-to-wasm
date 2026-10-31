extern fn bench_input() -> i64;
enum Event { Empty, Data { id: i64, values: i64[..] } }
fn prefix() -> i64 { print("prefix"); return 42; }
fn make(n: i64) -> Event.. { return Event.Data { prefix(), [..n] }; }
fn main() { let e = make(bench_input()); match e { Data p => print(p.id, " ", p.values.cap), _ => {} } }
