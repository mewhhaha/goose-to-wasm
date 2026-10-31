struct R<T>{tag:u8,small:varint,pad 2,next:T,large:varint,end:u16}
var zero:R<u16>;
var global=R<u16>{3,-65,300,9223372036854775807,500};
recursive fn make(n:i64)->R<u16>{return R<u16>{7,n,301,-9223372036854775808,501};}
recursive fn inspect(r:R<u16>)->i64{return r.small+r.next as i64;}
fn main(){
    let r=make(-8193);let kept:const varint& =r.small;
    let copied=copy(r);
    print(zero.tag as i64," ",zero.small," ",zero.next as i64," ",zero.large," ",zero.end as i64);
    print(global.tag as i64," ",global.small," ",global.next as i64," ",global.large," ",global.end as i64);
    print(r.tag as i64," ",kept," ",copied.small," ",copied.large," ",copied.end as i64," ",inspect(copy(r)));
}
