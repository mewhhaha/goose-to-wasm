var first:i64[4]=[17,34,51,68]; var second:i64[4]=[81,82,83,84];
var saved:i64[:]; var effects:i64=0;
fn write(xs:i64[:],index:i64,value:i64) { xs[index]=value; }
recursive fn next(n:i64)->i64 {
    effects=effects*10+n; if n==2 { saved=second[..]; } return n;
}
recursive fn drive() { write(saved,next(1),next(2)); write(saved,next(0),next(3)); }
fn main() { saved=first[..]; drive(); print(first[0]," ",first[1]," ",second[0]," ",second[1]," ",effects); }
