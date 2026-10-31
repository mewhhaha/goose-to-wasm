struct P<T>{pad 1,a:u8,pad,pad 2,b:T,pad 3}
struct Zero{pad 0,pad}
struct Mixed{tag:u8,pad,flag:bool,pad,word:u16,pad,number:f32,pad,point:i64&,pad,view:const u8[:],pad,items:u64[2]}
var global:i64=17;
var original=P<u32>{3,300};
recursive fn make(n:u32)->P<u32>{return P<u32>{17,n};}
fn changed(p:P<u32>)->P<u32>{p.b+=10;return p;}
fn consume(z:Zero)->i64{return 7;}
fn main(){
    let a=make(0x22334455);let b=changed(original);
    print(a.a as i64," ",a.b as i64," ",original.b as i64," ",b.b as i64," ",consume(Zero{}));
    let m=Mixed{17,true,300,1.5,global,"xy",[4,5]};
    print(m.tag as i64," ",m.flag," ",m.word as i64," ",m.number," ",m.point," ",m.view.len," ",m.items[1] as i64);
}
