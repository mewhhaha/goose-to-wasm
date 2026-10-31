recursive fn make(flag:bool)->varint[u8],i64{
    let a:varint[u8]=[1,-65];
    if flag{return a,17;}
    return[-9223372036854775808,64],23;
}
fn main(){
    for flag in [false,true]{
        let a,n=make(flag);let b:varint[u64]=copy(a);let c:varint[u16]=copy(b);
        print(a," ",n," ",b," ",c);
    }
}
