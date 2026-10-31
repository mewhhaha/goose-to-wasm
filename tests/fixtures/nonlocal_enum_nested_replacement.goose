enum E{A{v:u8},B{v:u8},Empty}
recursive fn overwrite()->i64{return E.B{7},9 from target;}
recursive fn escape(){return E.A{1},overwrite() from target;}
recursive fn target()->E..,i64{escape();return E.Empty,0;}
fn main(){let e,n=target();print(n);match e{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
