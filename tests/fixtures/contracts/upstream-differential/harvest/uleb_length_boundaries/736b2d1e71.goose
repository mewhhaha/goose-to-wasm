inline fn leave(){return[7;128] from target;}
inline fn target()->u8[varint]{leave();return[];}
fn main(){let a=target();print(a.len);}