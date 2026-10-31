struct R{n:varint,w:u16}
recursive fn make(b:bool)->R,i64,i64{
    let r=R{1,2};
    if b{return r,0,0;}
    return R{65,7},17,23;
}
fn main(){let r,a,b=make(false);print(r.n," ",r.w as i64," ",a," ",b);}
