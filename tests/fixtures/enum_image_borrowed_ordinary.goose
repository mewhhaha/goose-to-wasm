enum E{A{v:u8},B{v:u8},Empty}
var item:E.A=E.A{0x11};
recursive fn borrowed(x:i64)->const E.A& {print("borrowed ",x);return &item;}
fn arg()->i64{print("arg");return 7;}
fn main(){let e:E..=borrowed(arg());match e{A p=>print("A ",p.v as i64),_=>{}}}
