struct Item { n:i64 }
struct Slot { out:u8[..8] }
var slots:Slot[>..]=[Slot{out:[]};8];
fn format(out:u8[>..]&,v:Item){slots.push(Slot{out:[]});out.append("moved");}
fn main(){slots[0].out.format(Item{7});print(slots[0].out," ",slots[0].out.len," ",slots.len);}
