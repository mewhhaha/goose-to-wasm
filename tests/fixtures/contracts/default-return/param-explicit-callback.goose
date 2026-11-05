fn each<F>(n:i64){for i in n{F(i);}}
fn first(a:i64=block{each(3){i=>if i==1{return 21 from owner;}};0})->i64{a}
fn owner()->i64{first();0}
fn main(){print(owner());}
