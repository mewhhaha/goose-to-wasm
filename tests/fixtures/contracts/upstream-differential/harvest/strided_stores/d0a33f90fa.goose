var xs:u32[>..]=[17,34,51,68];
export fn paint(begin:i64,end:i64,stride:i64)->i64 {
    var cur=begin; var stop=end; var jump=stride;
    while cur<stop { xs[cur]=4045620583; cur+=jump; }
    return cur;
}
fn main() { print(paint(1,4,2)); xs=[17,34,51,68]; }
