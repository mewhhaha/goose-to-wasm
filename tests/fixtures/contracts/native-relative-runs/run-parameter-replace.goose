struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn replace(rows:Row[>..]&){ rows=[Row{2,self,"two"}]; }
fn main(){var rows:Row[>..]=[Row{1,self,"one"}];replace(rows);assert(rows.len==1);for r in rows{assert(r.me==r);print(r.me.id," ",r.me.text);}}
