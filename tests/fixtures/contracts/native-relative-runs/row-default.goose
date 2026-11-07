struct Row { id:i64=4, me:Row&<u32> = self, text:u8[]="default" }
fn main(){let r=Row{..};assert(r.me==r);print(r.me.id," ",r.me.text);}
