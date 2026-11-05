fn run(c:bool)->i64{let x:i64;fn setx(d:bool){fn bail(e:bool){if e{x=1;return from setx;}}bail(d);x=2;}setx(c);return x;}fn main(){print(run(true)," ",run(false));}
