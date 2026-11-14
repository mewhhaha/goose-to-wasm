var neighbor:i64[>..]=[987654321];
struct R{tag:u8,word:u16,values:varint[varint]}
recursive fn values()->varint[u32]{print(77);return[0;1];}
fn main(){let a=R{1,7,values()};print(a.values.len);}