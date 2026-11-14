var neighbor:i64[>..] = [987654321];
recursive fn leave(depth:i64,value:i64) {
    if depth > 0 { leave(depth-1,value); return; }
    return [value as u16,(value+1) as u16],[value as u16,(value+1) as u16] from target;
}
recursive fn target(depth:i64,value:i64) -> u16[u8],u16[..] {
    if depth > 0 { return target(depth-1,value); }
    leave(3,value); return [],[];
}
export fn tick(n:i64) -> i64 {
    var left,right=target(12,n);
    if left.len != 2 || right.len != 2 || right.cap != 2 || left[0] != n as u16 { abort("bad image escape"); }
    right.pop(); right.push((n+1) as u16); return right[1] as i64;
}
fn main() {}