struct P{pad 1,a:u8,pad,pad 2,b:u32,pad 3}
var rows:P[>..]=[P{0x11,0x22334455},P{0,0}];
export fn clone(){rows[1]=rows[0];}
fn main(){}