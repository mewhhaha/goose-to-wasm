struct R { tag:u8,values:u16[u8] }
struct L { tag:u8,values:u16[..] }
var neighbor:i64[>..] = [987654321];
recursive fn leave(depth:i64,value:i64) {
    if depth > 0 { leave(depth-1,value); return; }
    return R{7,[value as u16]},L{8,[(value+1) as u16]} from target;
}
recursive fn target(depth:i64,value:i64) -> R,L {
    if depth > 0 { return target(depth-1,value); }
    leave(3,value); return R{0,[]},L{0,[]};
}
export fn tick(n:i64) -> i64 {
    var left,right=target(12,n);
    if left.tag != 7 || right.tag != 8 || left.values.len != 1 || right.values.cap != 1 || right.values.len != 1 || left.values[0] != n as u16 { abort("bad record image escape"); }
    right.values.pop(); right.values.push((n+1) as u16); return right.values[0] as i64;
}
fn main() {}