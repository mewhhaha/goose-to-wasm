struct R{value:varint,after:u16}
recursive fn make(n:i64)->R{return R{n,0x2233};}
fn main(){
    for n in [-9223372036854775808,-8193,-8192,-65,-64,-1,0,1,63,64,8191,8192,9223372036854775807]{
        let r=make(n);print(r.value," ",r.after as i64);
    }
}
