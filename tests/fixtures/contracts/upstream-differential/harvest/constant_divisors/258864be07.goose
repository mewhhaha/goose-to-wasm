var order=0;
fn observe(tag:i64,value:i64)->i64 { order=order*10+tag; print(tag," ",order); return value; }
recursive fn mixed(a:i64,w:i64,tail:i64,h:i64,last:i64)->i64 { (a%w)*100+a%h+tail+last }
fn main() { print("before"); print(mixed(observe(1,-17),8,observe(2,100),0,observe(3,7))); }
