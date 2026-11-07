struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn make(i:i64)->Row{if i==1{return Row{1,self,"one"};}Row{i,self,"other"}}
fn relay(i:i64)->Row{make(i)}
fn main(){var rows:Row[>..]=[];rows.push(relay(1));rows.push(if true{relay(2)}else{Row{3,self,"bad"}});for r in rows{print(r.me.id," ",r.me.text);}}
