fn bench_input() -> i64 { return 5; }
var neighbor:i64[>..] = [987654321];
recursive fn target(depth:i64) -> u8[u8],u16[..] {
    if depth > 0 { return target(depth-1); }
    recursive fn leave() { return [7],[8] from target; }
    leave(); return [],[];
}
fn main() { let left,right=target(bench_input()); print(left.len,right.len); }