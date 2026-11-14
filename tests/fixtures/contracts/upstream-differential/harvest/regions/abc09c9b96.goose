fn bench_input() -> i64 { return 5; }
enum E {A{values:u8[u8]},B{values:u16[..]},Empty}
var neighbor:i64[>..] = [987654321];
recursive fn target(depth:i64)->E..,E.. {
    if depth>0 {return target(depth-1);}
    recursive fn leave() {return E.A{[7]},E.B{[8]} from target;}
    leave();return E.Empty,E.Empty;
}
fn main() {let left,right=target(bench_input());}