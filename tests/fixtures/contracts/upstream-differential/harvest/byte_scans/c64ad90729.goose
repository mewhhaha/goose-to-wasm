var xs:i8[64]=[-43;64];
export fn scan(begin:i64,end:i64,seed:i64)->i64 {
     var cur=begin; var count=seed; var last:i64=-99;
    while cur<end { if xs[cur]==-43 { last=cur; count++; } cur+=4; }
    return count+cur+last;
}
fn main() { print(scan(1,64,7)); print(scan(64,64,7)); print(scan(3,18,7)); }
