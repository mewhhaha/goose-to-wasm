struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn pair()->i64,i64{return 7,8;}
fn replace(rows:Row[>..]&){var a=0;var b=0;a,b=pair();rows=[Row{a+b,self,"new"}];}
fn main(){var rows:Row[>..]=[Row{1,self,"old"}];replace(rows);for r in rows{assert(r.me==r);print(r.me.id," ",r.me.text);}}
