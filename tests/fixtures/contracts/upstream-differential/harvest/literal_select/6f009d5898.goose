export fn casted(flag:bool,value:i64)->u8 { if flag { value as u8 } else { 7 } }
export fn literals(flag:bool)->u8 { if flag { 1 as! u8 } else { 2 as! u8 } }
fn main() { print(casted(false,256)); print(casted(true,256)); }