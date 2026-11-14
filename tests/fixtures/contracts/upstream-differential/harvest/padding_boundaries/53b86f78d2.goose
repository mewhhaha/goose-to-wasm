struct P{a:u8,pad 1,b:u16}
fn target()->P[u8]{recursive fn leave(){return [P{1,2}] from target;}leave();return [];}
fn main(){let p=target();print(p.len);}