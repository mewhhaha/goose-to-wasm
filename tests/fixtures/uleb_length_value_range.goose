enum C{A,B}recursive fn values(c:C.A)->u8[u8]{let x:u8[u16]=[7;256];return x[..];}recursive fn values(c:C.B)->u8[u8]{let x:u8[u16]=[8;256];return x[..];}
fn main(){let c:C=C.A;let a:u8[varint]=values(c);print(a.len);}
