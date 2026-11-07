import std;
struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn main(){ let xs=[1,2,3]; let rs=map(xs){Row{it,self,str(it)}}; for r in rs { print(r.me.id," ",r.me.text); } }
