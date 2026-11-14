struct R {tag:u8,pad 3,word:u16,pad,values:u8[u8]}
var neighbor:i64[>..]=[987654321];
recursive fn make(n:i64)->R {return R{7,n as u16,[8]};}
export fn tick(n:i64)->i64 {
    let r=make(n);let kept:const u16& =r.word;
    for i in 10 {if make(i).word!=i as u16 {abort("bad padded temporary");}}
    if kept!=n as u16 || r.values.len!=1 || r.values[0]!=8 {abort("bad padded reference");}
    return n+1;
}
fn main() {}