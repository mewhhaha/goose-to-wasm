struct R { x:u8[..1] }
var target=R { x:default<u8[2]>() };
export fn dirty() { target.x=[7]; }
export fn read()->i64 { return target.x.len*100+target.x[0] as i64; }
fn main() {}
