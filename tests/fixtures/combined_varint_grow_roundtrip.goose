recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
recursive fn make(n:i64)->varint[varint]{var a:varint[>..]=[n];a.push(64);a.push(-65);return a;}
recursive fn raw()->varint[>..]{let a:varint[varint]=[8192;128];return copy(a);}
fn main(){let a=make(9);var b:varint[>..]=copy(a);b.append(a);print(a," ",b);let c:varint[varint]=raw();print(c.len," ",at(c,127));}