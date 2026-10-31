enum E{A{v:u8},B{v:u8},Empty}
recursive fn variant(x:u8)->E.A{return E.A{x};}
inline fn target<F>()->E..{F();return E.Empty;}
inline fn jump(){return variant(1) from target;}
fn main(){let e=target(){jump()};match e{A=>print("A"),B=>print("B"),Empty=>print("Empty")}}
