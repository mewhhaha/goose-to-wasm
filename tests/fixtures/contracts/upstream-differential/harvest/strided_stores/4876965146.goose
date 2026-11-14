var xs:u32[>..]=[17,34,51,68];
recursive fn attempt(begin:i64,end:i64,stride:i64)->i64 {
    var cur=begin; var stop=end; var jump=stride;
    while cur<stop { xs[cur]=4045620583; cur+=jump; }
    return cur;
}
fn main() { print(attempt(1,0,2)); }
