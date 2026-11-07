struct Row { id:i64, pad 0, me:Row&<u32>, pad 3, text:u8[varint] }
fn main(){var rows:Row[>..]=[];rows.push(Row{1,self,""});rows.push(Row{2,self,"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"});for r in rows{assert(r.me==r);print(r.me.id," ",r.me.text.len);}}
