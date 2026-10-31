extern fn bench_input() -> i64;
enum Payload { Bytes { id: i64, values: u8[u8] }, Growing { values: u8[>..] } }
fn prefix() -> i64 { print("prefix"); return 42; }
fn bytes(n: i64) -> u8[u64] { print("tail"); var values: u8[>..] = []; values.resize(n, 7); return values; }
fn make(n: i64) -> Payload.Bytes { return Payload.Bytes { prefix(), bytes(n) }; }
fn main() { let p = make(bench_input()); print(p.id, " ", p.values.len, " ", p.values[0]); }
