fn apply<F>(){F();} fn run(c:bool){let x:i64;fn rd(){print(x);}if c{x=7;apply(rd);}apply(rd);}fn main(){run(false);}
