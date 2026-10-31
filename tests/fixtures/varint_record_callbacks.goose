struct R{first:varint,pad 3,last:varint,end:u8}
fn step(n:i64)->i64{print(n);return n;}
fn build<F>()->R{return R{step(11),F(),7};}
fn target(escape:bool)->i64{
    let r=build(){if escape{return 99;}else{step(-65)}};
    return r.first+r.last+r.end as i64;
}
recursive fn pair()->R,i64{return R{step(17),step(64),8},step(23);}
fn main(){print(target(true));print(target(false));let r,n=pair();print(r.first," ",r.last," ",r.end as i64," ",n);}
