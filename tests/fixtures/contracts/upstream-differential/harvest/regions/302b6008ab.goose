fn bench_input() -> i64 { return 5; }
struct Packet { id: i64, values: i64[>..] }
var packet = Packet { 1, [2] };
var neighbor: i64[>..] = [987654321];
fn replace(target: Packet&) {
    target = Packet { 3, [if bench_input() > 0 { return; } else { 4 }; 1000000] };
}
fn main() { replace(packet); }