var saved:i8[:]; var backing:i8[4]=[17,34,51,68];
var final_cur:i64=-777; var final_last:i64=-888; var effects:i64=0;
export fn scan(begin:i64,end:i64,seed:i64)->i64 {
    let xs=saved; var cur=begin; var count=seed; var last:i64=-99;
    while cur<end { if xs[cur]==-1 { last=cur; count++; } cur++; }
    final_cur=cur; final_last=last; return count;
}
export fn cursor()->i64 { return final_cur; }
export fn latest()->i64 { return final_last; }
fn main() { saved=backing[..]; }
