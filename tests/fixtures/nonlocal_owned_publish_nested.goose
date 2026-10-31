recursive fn enable(n:i64){if n>0{enable(n-1);return;}return [99] from enabled;}
fn enabled()->i64[>..]{enable(1);return [];}
struct Inner{id:i64,values:i64[>..]}
struct Outer{tag:i64,child:Inner}
var g=Outer{9,Inner{8,[7]}};
fn inner<C>()->Inner{return Inner{1,[C();16]};}
fn outer<C>()->Outer{return Outer{2,inner(){C()}};}
fn find(flag:bool)->i64{g=outer(){if flag{return 7;}4};0}
fn main(){print(enabled());print(find(true)," ",g.tag," ",g.child.id," ",g.child.values.len," ",g.child.values[0]);}
