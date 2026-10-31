recursive fn make(depth:i64) -> u8[u16],u16[..],i64[>..],i64 {
    if depth > 0 { return make(depth-1); } return [7,8],[9,10],[11],17;
}
recursive fn leave(depth:i64) {
    if depth > 0 { leave(depth-1); return; } return make(4) from target;
}
recursive fn target() -> u8[u16],u16[..],i64[>..],i64 {
    var left:u8[u16] = [1,2]; var right:u16[..] = [..5]; right.push(1);
    var third:i64[>..] = [3]; leave(4); return left,right,third,0;
}
fn main() {
    var left,right,third,n = target();
    print(left.len," ",left[0] as i64," ",left[1] as i64);
    print(right.cap," ",right.len," ",right[0] as i64," ",right[1] as i64);
    print(third," ",n); print(right.pop() as i64); right.push(12); print(right[1] as i64);
}
