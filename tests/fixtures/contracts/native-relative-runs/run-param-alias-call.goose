struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn relay(a:i64,rows:Row[>..]&,b:i64){let alias=rows;alias.push(Row{a+b,self,"x"});}
fn invoke<F>(a:i64,rows:Row[>..]&,b:i64){F(a,rows,b);}
fn main(){var rows:Row[>..]=[];relay(1,rows,2);invoke(4,rows,5,relay);assert(rows.len==2);for r in rows{print(r.me.id," ",r.me.text);}}
