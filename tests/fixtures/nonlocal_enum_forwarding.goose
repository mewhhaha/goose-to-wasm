enum E{A{v:u8},B{v:u8},Empty}
recursive fn make()->E..,i64,E..{return E.A{3},5,E.B{7};}
recursive fn leave(){return make() from target;}
recursive fn target()->E..,i64,E..{leave();return E.Empty,0,E.Empty;}
fn main(){let a,n,b=target();print(n);match a{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>{}} match b{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>{}}}
