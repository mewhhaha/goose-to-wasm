var saved:u8[:]; var backing:u8[4]=[17,34,51,68];
var final_cur:i64=-777; var final_last:i64=-888; var effects:i64=0;
export fn scan(begin:i64,end:i64,seed:i64)->i64 {
    let xs=saved; var cur=begin; var count=seed; var last:i64=-99;
    while cur<end { if xs[cur]==213 { last=cur; count++; effects+=(xs[cur] as i64); } cur+=1; }
    final_cur=cur; final_last=last; return count;
}
export fn cursor()->i64 { return final_cur; }
export fn latest()->i64 { return final_last; }
fn main() { saved=backing[..]; }
