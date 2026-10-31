recursive fn encoded(xs:const varint[:])->varint[varint]{print("encoded");return xs;}
fn main(){let source:varint[u16]=[7;256];let a:varint[u8]=encoded(source);print(a.len);}
