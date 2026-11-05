struct S{a:i64=block{return 1 from main;}}
fn main()->i64{print(S{}.a);0}
