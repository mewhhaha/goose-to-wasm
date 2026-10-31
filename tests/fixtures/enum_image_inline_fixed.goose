enum E{A{v:u8},B{v:u8},Empty}
inline fn variant(x:u8)->E.A{return E.A{x};}
fn make(b:bool)->E..{return variant(if b{return E.B{0x22};}else{7});}
fn main(){let e=make(true);match e{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
