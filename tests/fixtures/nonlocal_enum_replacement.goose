enum E{A{v:u8},B{v:u8},Empty}
recursive fn leave(){return E.B{7} from target;}
recursive fn target()->E..{var own:E..=E.A{1};leave();return own;}
fn main(){let e=target();match e{A p=>print("A ",p.v as i64),B p=>print("B ",p.v as i64),Empty=>print("Empty")}}
