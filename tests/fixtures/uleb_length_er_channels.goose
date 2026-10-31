recursive fn narrow(xs:const u8[:])->u8[u8]{print("narrow");return xs;}
recursive fn encoded(xs:const u8[:])->u8[varint]{print("encoded");return xs;}
fn main(){let source:u8[u16]=[7;256];let a:u8[varint]=narrow(source);let b:u8[u16]=encoded(source);var out:u8[>..]=[9];out.append(encoded(source));print(a.len," ",b.len," ",out.len," ",a[255] as i64," ",b[255] as i64);}
