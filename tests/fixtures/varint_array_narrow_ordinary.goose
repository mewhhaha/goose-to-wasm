recursive fn narrow(xs:const varint[:])->varint[u8]{print("make");return xs;}
fn main(){let source:varint[u16]=[-65;256];let a:varint[u16]=narrow(source);var s=0;for x in a{s+=x;}print(a.len," ",s);}
