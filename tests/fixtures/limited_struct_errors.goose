extern fn bench_input() -> i64;
struct Packet { id: i64, values: i64[..] }
fn prefix() -> i64 { print("prefix"); return 1; }
fn main() { let packet = Packet { prefix(), [..bench_input()] }; print(packet.values.cap); }
