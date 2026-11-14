struct R{tag:u8,word:u16,values:varint[varint]}
var row=R{0x11,0x2233,[64,-65]};
export fn clone()->i64{let r=copy(row);var total=0;for n in r.values{total+=n;}return total;}
export fn length()->i64{row.values.len}
fn main(){}