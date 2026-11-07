struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn make(i:i64)->Row { Row{i,self,str(i)} }
fn relay(i:i64)->Row { if i>0 { return make(i); } make(0) }
fn main(){ let r=relay(12); assert(r.me==r); print(r.me.id," ",r.me.text); }
