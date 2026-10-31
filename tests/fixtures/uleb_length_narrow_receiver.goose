recursive fn encoded(xs:const u8[:])->u8[varint]{print("encoded");return xs;}
fn main(){let source:u8[u16]=[7;256];let a:u8[u8]=encoded(source);print(a.len);}
