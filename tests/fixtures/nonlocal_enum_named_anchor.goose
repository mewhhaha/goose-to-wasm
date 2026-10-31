enum E{A{a:u8,b:u8},B{v:u8},Empty}
recursive fn stop()->u8{return 9 from canceled;}
recursive fn canceled()->i64{return E.A{0x11,stop()} from target;}
recursive fn target()->E..{print(canceled());var own:E..=E.B{0x44};match own{B p=>print(p.v as i64),_=>{}} return own;}
fn main(){let e=target();match e{A p=>print("A ",p.a as i64," ",p.b as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
