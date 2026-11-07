struct Row { id:i64, me:Row&<u32>, text:u8[] }
var root=Row{1,self,"one"};
var order=0;
fn mark(n:i64)->i64 { order=order*10+n; n }
fn text()->u8[] { order=order*10+3; print(root.me.id," ",root.me.text); "next" }
fn main(){ let fresh=Row{mark(2),self,text()}; assert(order==23); assert(fresh.me==fresh); print(fresh.me.id," ",fresh.me.text); }
