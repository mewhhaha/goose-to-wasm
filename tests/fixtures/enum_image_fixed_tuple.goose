enum E {Empty,A{v:u8},B{v:u16}}
recursive fn pair()->E.A,E.B,i64{return E.A{7},E.B{300},17;}
recursive fn wrapped()->E..,E..,i64{return pair();}
fn main(){let a,b,n=wrapped();match a{A p=>print(p.v as i64),_=>{}} match b{B p=>print(p.v as i64," ",n),_=>{}}}
