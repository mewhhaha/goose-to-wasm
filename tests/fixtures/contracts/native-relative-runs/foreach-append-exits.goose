struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn main(){var rows:Row[>..]=[Row{1,self,"one"}];var sum=0;for r in rows{sum+=r.me.id;if r.me.id==1{rows.push(Row{2,self,"two"});continue;}rows.push(Row{3,self,"three"});break;}assert(sum==3&&rows.len==3);for r in rows{print(r.me.id," ",r.me.text);}}
