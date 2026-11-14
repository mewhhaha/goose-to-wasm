recursive fn leave(){return[64;128] from target;}
recursive fn target()->varint[varint]{leave();return[];}
fn main(){let a=target();print(a.len);}