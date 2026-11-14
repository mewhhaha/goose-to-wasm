struct R{tag:varint,values:varint[varint]}
fn make()->R{return R{1,[64,-65]};} fn main(){let r=make();print(r.values.len);}