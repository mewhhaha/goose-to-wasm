enum E{Data{id:u8,values:u8[u32]},Empty}
recursive fn stop()->u8{return 9 from canceled;}
recursive fn canceled()->i64{return E.Data{0x11,[stop();70000]} from target;}
recursive fn target()->E..{print(canceled());return E.Empty;}
fn main(){let e=target();match e{Data &p=>print(p.id as i64," ",p.values.len," ",p.values[0] as i64," ",p.values[66000] as i64),Empty=>print("Empty")}}
