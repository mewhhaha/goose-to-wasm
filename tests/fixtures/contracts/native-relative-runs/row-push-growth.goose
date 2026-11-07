struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn main(){ var rows:Row[>..]=[]; let first .= rows.push(Row{1,self,"one"}); for i in 128 { rows.push(Row{i+2,self,str(i+2)}); } assert(first.me==first); print(first.me.id," ",first.me.text); for r in rows { assert(r.me==r); } }
