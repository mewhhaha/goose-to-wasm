struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn main(){ let r=Row{9,self,"alpha"}; assert(r.me==r); print(r.me.id," ",r.me.text); }
