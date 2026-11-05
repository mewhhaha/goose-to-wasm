let K=3;
fn neg(x:i64&){x=-1;}
fn choose(tag:i64)->i64 {
    let n=match tag{0=>{return K;},_=>5};
    let u:u64=18446744073709551615;assert(u>n);return n;
}
fn main(){neg(K);print(choose(0)," ",choose(1));}
