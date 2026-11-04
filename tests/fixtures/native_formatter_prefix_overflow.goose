struct Item { n:i64 }
var target:u8[..3]=[];
fn format(out:u8[>..]&,v:Item){out.push(120);print(target);out.push(121);print(target);out.append("zz");}
fn main(){target.format(Item{7});}
