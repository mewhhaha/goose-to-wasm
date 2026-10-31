extern fn bench_input() -> i64;
struct Small { id: i64, values: u8[u8] }
fn prefix() -> i64 { print("prefix"); return 42; }
recursive fn bytes(n: i64) -> u8[u64] {
    print("tail"); var values: u8[>..] = []; values.resize(n, 7); return values;
}
fn make(n: i64) -> Small { return Small { prefix(), bytes(n) }; }
fn main() { let packet = make(bench_input()); print(packet.id, " ", packet.values.len, " ", packet.values[0]); }
