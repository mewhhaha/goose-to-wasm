struct S{a:i64=block{let n:i64=20;fn helper()->i64{return n;} helper()}}
fn main(){print(S{}.a);}
