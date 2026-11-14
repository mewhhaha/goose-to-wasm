struct R{tag:u8,values:varint[u8]}
inline fn leave(){return R{1,[7;128]} from target;}
inline fn target()->R{leave();return R{2,[]};}
fn main(){let r=target();print(r.values.len);}