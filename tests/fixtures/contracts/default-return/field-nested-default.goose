struct Inner{a:i64=block{return 1 from local;}}
struct S{a:i64=block{fn local()->i64{Inner{}.a} local()}}
fn main(){print(S{}.a);}
