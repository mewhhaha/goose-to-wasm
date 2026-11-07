struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn make(first:bool)->Row {
 if first {return Row{1,self,"one"};}
 Row{2,self,"two"}
}
fn main(){
 var rows:Row[>..]=[];
 rows.push(make(true)); rows.push(make(false));
 for r in rows {print(r.me.id," ",r.me.text);}
}
