var count:i64=0;
fn bump()->i64{count+=1;count}
fn first(a:i64=bump())->i64{a}
struct S{a:i64=bump()}
fn main(){print(first()," ",S{}.a," ",count);}
