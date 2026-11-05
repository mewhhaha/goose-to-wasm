fn call<F>()->i64{F()}
fn first(a:i64=block{let k=call(){block{break 15;}};break k;})->i64{a}
fn main(){print(first());}
