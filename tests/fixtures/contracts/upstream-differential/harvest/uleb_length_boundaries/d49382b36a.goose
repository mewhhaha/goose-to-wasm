recursive fn leave(){return[7;128] from target;}
recursive fn target()->u8[varint]{leave();return[];}
fn main(){let a=target();print(a.len);}