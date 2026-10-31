enum C{A,B}recursive fn values(c:C.A)->u8[varint]{return[7;128];}recursive fn values(c:C.B)->u8[varint]{return[8;127];}
fn main(){for flag in[false,true]{let c:C=if flag{C.A}else{C.B};let a:u8[u16]=values(c);var out:u8[>..]=[9];out.append(values(c));print(a.len," ",a[0] as i64," ",out.len," ",out[1] as i64);}}
