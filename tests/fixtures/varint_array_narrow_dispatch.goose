enum C{A,B}
recursive fn narrow(c:C.A,xs:const varint[:])->varint[u8]{print("A");return xs;}
recursive fn narrow(c:C.B,xs:const varint[:])->varint[u8]{print("B");return xs;}
fn main(){let source:varint[u16]=[-65;256];let c:C=C.A;let a:varint[u16]=narrow(c,source);print(a.len);}
