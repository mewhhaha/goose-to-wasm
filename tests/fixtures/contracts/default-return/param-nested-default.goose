fn inner(a:i64=block{return 1 from local;})->i64{a}
fn first(a:i64=block{fn local()->i64{inner()} local()})->i64{a}
fn main(){print(first());}
