fn apply<F>(a:varint[varint])->varint[varint]{return F(copy(a));}
fn main(){let a:varint[varint]=[64,-65,8192];let b=apply(copy(a)){xs:varint[varint]=>copy(xs)};print(a," ",b);}
