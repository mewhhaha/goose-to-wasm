let K=3; let L=5;
fn choose(tag:i64, take:bool)->i64 {
    let n=match tag {0=>if take {K}else{match tag{0=>L,_=>7}},_=>9};
    let u:u64=18446744073709551615; assert(u>n); return n;
}
fn main(){let before:const i64& = K;print(choose(0,true)," ",choose(0,false)," ",choose(1,false));let after:const i64& = L;assert(before==3&&after==5);}
