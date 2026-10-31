enum E{A{a:u8,b:u8},B{v:u16},Empty}
recursive fn stop()->u8{return 9 from canceled;}
recursive fn canceled()->i64{return E.A{0x11,stop()} from target;}
recursive fn target()->E..{print(canceled());return E.B{0x2233};}
fn main(){let e=target();match e{A p=>print("A ",p.a as i64," ",p.b as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
