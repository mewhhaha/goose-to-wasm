inline fn leave(){return[64;128] from target;}
inline fn target()->varint[varint]{leave();return[];}
fn main(){let a=target();print(a.len);}