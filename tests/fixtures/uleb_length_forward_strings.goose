recursive fn word()->u8[varint]{return"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";}
inline fn inlineword()->u8[varint]{return"qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq";}
fn main(){let a:u8[u16]=word();var b:u8[>..]=[];b.append(word());let c:u8[varint]=inlineword();print(a.len," ",a[127] as i64," ",b.len," ",b[127] as i64," ",c.len);}
