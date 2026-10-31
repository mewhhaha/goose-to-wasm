recursive fn values(xs:const varint[:])->varint[u8]{print("value");return xs;}fn main(){let a:varint[u16]=[-65;256];var out:varint[>..]=[1];out.append(values(a));print(out.len);}
