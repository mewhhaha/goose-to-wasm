struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn main(){var rows:Row[>..]=[Row{1,self,"one"},Row{2,self,"two"}];for &r in rows{r.id+=10;assert(r.me==r);}for r in rows{print(r.me.id," ",r.me.text);}}
