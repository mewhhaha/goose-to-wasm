fn run(c:bool)->i64{let x:i64;fn target(d:bool){fn step(e:bool){if e{x=1;return from target;}x=2;}step(d);}target(c);return x;}fn main(){print(run(true)," ",run(false));}
