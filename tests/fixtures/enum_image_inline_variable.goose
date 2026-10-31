enum E{A{head:u8,values:u8[u8]},B{head:u8,values:u8[u8]},Empty}
inline fn variant(x:u8)->E.A{return E.A{0x11,[x]};}
fn make(b:bool)->E..{return variant(if b{return E.B{0x22,[0x33]};}else{7});}
fn main(){let e=make(true);match e{A p=>print("A ",p.head as i64," ",p.values.len," ",p.values[0] as i64),B p=>print("B ",p.head as i64," ",p.values.len," ",p.values[0] as i64),Empty=>print("Empty")}}
