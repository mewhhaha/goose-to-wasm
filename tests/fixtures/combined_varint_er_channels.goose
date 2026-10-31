recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
recursive fn narrow(xs:const varint[:])->varint[u8]{print("narrow");return xs;}
recursive fn encoded(xs:const varint[:])->varint[varint]{print("encoded");return xs;}
fn main(){let source:varint[u16]=[7;256];let a:varint[varint]=narrow(source);let b:varint[u16]=encoded(source);var out:varint[>..]=[9];out.append(encoded(source));print(a.len," ",b.len," ",out.len," ",at(a,255) as i64," ",at(b,255) as i64);}
