struct R {value:varint,other:varint,end:u8}
var neighbor:i64[>..]=[987654321];
recursive fn make(n:i64)->R {return R{n-5000,-n,7};}
export fn tick(n:i64)->i64 {
    let r=make(n);let kept:const varint& =r.value;
    for i in 10 {if make(i).other!=-i {abort("bad varint temporary");}}
    if kept!=n-5000 || r.other!=-n || r.end!=7 {abort("bad varint reference");}
    return n+1;
}
fn main() {}