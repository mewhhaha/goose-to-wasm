struct P{lo:u8,hi:u16}recursive fn make()->P[varint]{return[P{1,0x2233};128];}fn main(){let a=make();let b:P[u16]=copy(a);print(a.len," ",a[127].lo as i64," ",b[127].hi as i64);}
