var order=0; var calls=0;
fn observe(tag:i64,value:i64)->i64 {
    order=order*10+tag; calls++; print(tag," ",order); return value;
}
recursive fn partial(a:i64,w:i64,tail:i64,h:i64,last:i64)->i64 { (a%w)*100+a%h+tail+last }
fn main() {order=0; calls=0; print(partial(observe(1,-17),8,observe(2,100),observe(3,0),observe(4,7))," ",order," ",calls);}