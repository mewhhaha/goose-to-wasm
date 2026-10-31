struct R{tag:varint,values:varint[varint]}
fn main(){let r=R{1,[64,-65]};print(r.values.len);}
