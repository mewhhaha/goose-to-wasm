fn bench_input() -> i64 { return 5; }
struct R { tag:u8,values:u8[u8] }
struct L { tag:u8,values:u16[..] }
var neighbor:i64[>..] = [987654321];
recursive fn target(depth:i64) -> R,L {
    if depth > 0 { return target(depth-1); }
    recursive fn leave() { return R{1,[7]},L{2,[8]} from target; }
    leave(); return R{0,[]},L{0,[]};
}
fn main() { let left,right=target(bench_input()); print(left.values.len,right.values.len); }