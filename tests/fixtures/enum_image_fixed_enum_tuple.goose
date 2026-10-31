enum E{A{v:u8},B{v:u8},Empty}
recursive fn pair()->E,i64{return E.B{7},3;}
recursive fn outer(b:bool)->E..,i64{return E.A{if b{return pair();}else{1}},0;}
fn main(){let e,n=outer(true);print(n);match e{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
