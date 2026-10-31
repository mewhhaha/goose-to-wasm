struct R { tag:u8,word:u16,values:u8[u8] }
fn bump(r:R&) -> u16 { r.word=99; r.values[0]=88; return r.word; }
recursive fn maker() -> R,u16,R { var r=R{1,7,[8]}; return r,bump(r),r; }
fn main() {
    let a,n,b=maker(); print(a.tag as i64," ",a.word as i64," ",a.values[0] as i64," ",n as i64," ",b.word as i64);
}
