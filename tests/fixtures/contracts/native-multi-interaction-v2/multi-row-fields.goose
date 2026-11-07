struct Row { id:i64, me:Row&<u32>, text:u8[] }
var calls=0;
fn pair()->i64,i64{calls++;return 7,8;}
fn main(){var rows:Row[>..]=[];let r .= rows.push(Row{1,self,"one"});var x=0;r.id,x=pair();assert(calls==1&&r.me==r);print(r.me.id," ",r.me.text," ",x);}
