fn call<F>()->i64{F()}
struct S{a:i64=block{let k=call(){block{break 16;}};break k;}}
fn main(){print(S{}.a);}
