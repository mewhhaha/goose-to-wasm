
export fn scan(begin:i64,end:i64,seed:i64)->i64 {
    var xs:u8[64]=[213;64]; var cur=begin; var count=seed; var last:i64=-99;
    while cur<end { if xs[cur]==213 { last=cur; count++; } cur+=4; }
    return count+cur+last;
}
fn main() { print(scan(1,64,7)); print(scan(64,64,7)); print(scan(3,18,7)); }
