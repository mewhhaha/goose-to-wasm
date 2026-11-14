var values:varint[varint]=[64,-65];
export fn clone()->i64{let rows=copy(values);var total=0;for n in rows{total+=n;}return total;}
export fn length()->i64{values.len}
fn main(){}