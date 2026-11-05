fn run(c:bool){let y:i64;fn target(a:bool,b:bool){fn leave(){return from target;}if a{leave();}if b{leave();}y=1;leave();}target(c,c);y=2;print(y);}fn main(){run(false);}
