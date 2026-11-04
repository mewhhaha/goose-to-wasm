struct Item { n:i64 }
fn format(out:u8[>..]&,v:Item){out.append("<");out.format(v.n);out.append(">");}
fn main(){var out:u8[..8]=[];out.format(Item{7});print(out," ",out.len);}
