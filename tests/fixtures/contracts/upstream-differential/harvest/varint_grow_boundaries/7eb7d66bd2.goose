recursive fn grow(a:varint[>..]&)->i64{a.push(8192);return a.len;}
recursive fn make()->varint[u8],i64,varint[u16]{var a:varint[>..]=[1,64];return a,grow(a),copy(a);}
fn main(){let a,n,b=make();print(a," ",n," ",b);}