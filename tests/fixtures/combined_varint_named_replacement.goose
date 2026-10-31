recursive fn make(flag:bool)->varint[varint],i64{
    let a:varint[varint]=[1,-65];
    if flag{return a,17;}
    return[-9223372036854775808,64],23;
}
fn main(){
    for flag in [false,true]{
        let a,n=make(flag);let b:varint[varint]=copy(a);let c:varint[varint]=copy(b);
        print(a," ",n," ",b," ",c);
    }
}
