struct Pair { first:i64, second:i64 }
var backing:u8[2]=[4,5];
recursive fn borrowed(p:Pair)->const u8[:] { if p.first>0 { return backing[..]; } return backing[..0]; }
fn main() { let view=borrowed(Pair { 1,2 }); print(view[0]," ",view.len); }
