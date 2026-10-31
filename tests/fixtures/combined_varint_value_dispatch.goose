recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
enum C{A,B}recursive fn values(c:C.A)->varint[varint]{return[7;128];}recursive fn values(c:C.B)->varint[varint]{return[8;127];}
fn main(){for flag in[false,true]{let c:C=if flag{C.A}else{C.B};let a:varint[u16]=values(c);var out:varint[>..]=[9];out.append(values(c));print(a.len," ",at(a,0) as i64," ",out.len," ",at(out,1) as i64);}}
