enum E{A{v:u8},B{v:u8},Empty}
recursive fn variant(x:u8)->E.A{return E.A{x};}
inline fn target<F>()->E..{print(F());return E.B{0x44};}
inline fn canceled()->i64{return variant(stop()) from target;}
inline fn stop()->u8{return 9 from canceled;}
fn main(){let e=target(){canceled()};match e{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
