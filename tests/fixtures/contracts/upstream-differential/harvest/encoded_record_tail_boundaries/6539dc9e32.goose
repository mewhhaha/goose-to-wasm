struct R{tag:u8,values:u8[varint]}
recursive fn leave(){return R{1,[7;128]} from target;}
recursive fn target()->R{leave();return R{2,[]};}
fn main(){let r=target();print(r.values.len);}