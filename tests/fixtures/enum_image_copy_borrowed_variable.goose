enum E{A{v:u8,values:u8[u8]},B{v:u8,values:u8[u8]},Empty}
var item:E.A=E.A{0x11,[0x22]};
recursive fn borrowed(x:u8)->const E.A& {return &item;}
inline fn target<F>()->E..{print(F());return E.B{0x44,[0x55]};}
inline fn canceled(b:bool)->i64{return copy(borrowed(stop(b))) from target;}
inline fn stop(b:bool)->u8{if b{return 9 from canceled;}return 7;}
fn main(){let e=target(){canceled(true)};match e{A p=>print("A ",p.v as i64," ",p.values.len),B p=>print("B ",p.v as i64," ",p.values.len," ",p.values[0] as i64),Empty=>print("Empty")}}
