var saved:u16[:]; var backing:u16[4]=[17,34,51,68];
var effects:i64=0;
export fn paint(begin:i64,end:i64,stride:i64)->i64 {
    let xs=saved; var cur=begin; var stop=end; var jump=stride;
    while cur<stop { xs[cur]=42480; cur+=jump; }
    return cur;
}
fn main() { saved=backing[..]; print(paint(1,4,2)); backing=[17,34,51,68]; }
