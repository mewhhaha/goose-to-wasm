struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn text()->u8[] {"ok"}
fn main(){let r=Row{3,self,text()}; assert(r.me==r); print(r.me.id," ",r.me.text);}
