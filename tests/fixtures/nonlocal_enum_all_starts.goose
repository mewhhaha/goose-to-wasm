enum E{A{v:u8},B{v:u8},Empty}
recursive fn stop()->u8{return 9 from canceled;}
recursive fn canceled()->i64{return 0,E.A{0x11},E.A{stop()} from target;}
recursive fn first()->i64{print(canceled());return 7;}
recursive fn escape(){return first(),E.B{0x44},E.B{0x55} from target;}
recursive fn target()->i64,E..,E..{escape();return 0,E.Empty,E.Empty;}
fn main(){let n,a,b=target();print(n);match a{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>{}} match b{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>{}}}
