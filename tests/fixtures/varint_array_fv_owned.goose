fn apply<F>(a:varint[u16])->varint[u16]{return F(copy(a));}
fn main(){let a:varint[u16]=[64,-65,8192];let b=apply(copy(a)){xs:varint[u16]=>copy(xs)};print(a," ",b);}
