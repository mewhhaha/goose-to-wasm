struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn read(r:Row&) { let a=r; print(a.me.id," ",a.me.text); }
fn main(){ let r=Row{1,self,"one"}; read(r); read(r); }
