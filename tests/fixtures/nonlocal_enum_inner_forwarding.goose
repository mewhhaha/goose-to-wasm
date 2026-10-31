enum E{A{v:u8},B{v:u8},Empty}
recursive fn stop()->u8{return 9 from canceled;}
recursive fn canceled()->i64{return E.A{17},0,E.A{stop()} from outer;}
recursive fn inner_escape(){return E.B{0x44},7,E.B{0x55} from inner;}
recursive fn inner()->E..,i64,E..{inner_escape();return E.Empty,0,E.Empty;}
recursive fn outer()->E..,i64,E..{print(canceled());return inner();}
fn main(){let a,n,b=outer();print(n);match a{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")} match b{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
