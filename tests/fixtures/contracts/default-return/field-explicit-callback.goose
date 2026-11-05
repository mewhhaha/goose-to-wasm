fn each<F>(n:i64){for i in n{F(i);}}
struct S{a:i64=block{each(3){i=>if i==1{return 22 from owner;}};0}}
fn owner()->i64{let s=S{};s.a}
fn main(){print(owner());}
