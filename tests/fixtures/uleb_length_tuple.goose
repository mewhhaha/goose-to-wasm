recursive fn pair(n:i64)->u8[varint],i64,u16[varint]{return[n as u8;128],n+1,[0x1234;16384];}
recursive fn relay(n:i64)->u8[varint],i64,u16[u32]{return pair(n);}
fn main(){let a,n,b=relay(9);print(a.len," ",a[127] as i64," ",n," ",b.len," ",b[16383] as i64);}
