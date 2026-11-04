struct Item { n:i64 }
fn format(out:u8[>..]&,v:Item){out.push(97);fn done(){out.push(98);return from format;}done();out.push(99);}
fn main(){var out:u8[..8]=[];out.format(Item{7});print(out," ",out.len);}
