struct S{a:i64=block{fn unused()->i64{return 13;} 14}}
fn main(){print(S{}.a);}
