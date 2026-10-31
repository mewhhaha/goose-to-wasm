struct R { tag:u8,word:u16,values:u8[u8] }
struct L { tag:u8,word:u16,values:u16[..] }
recursive fn make(depth:i64) -> R,L,i64[>..],i64 {
    if depth > 0 { return make(depth-1); } return R{7,300,[8,9]},L{10,400,[11,12]},[13],17;
}
recursive fn leave(depth:i64) { if depth > 0 { leave(depth-1); return; } return make(12) from target; }
recursive fn target() -> R,L,i64[>..],i64 {
    var left=R{1,2,[3]}; var right=L{4,5,[..4]}; var third:i64[>..]=[6];
    leave(4); return left,right,third,0;
}
fn main() {
    var a,b,c,n=target();
    print(a.tag as i64," ",a.word as i64," ",a.values.len," ",a.values[0] as i64," ",a.values[1] as i64);
    print(b.tag as i64," ",b.word as i64," ",b.values.cap," ",b.values.len," ",b.values[0] as i64," ",b.values[1] as i64);
    print(c," ",n); print(b.values.pop() as i64); b.values.push(14); print(b.values[1] as i64);
}
