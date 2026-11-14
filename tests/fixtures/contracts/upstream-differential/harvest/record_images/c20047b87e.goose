struct R {tag:u8,word:u16,values:u8[..]} var r=R{0x11,0x2233,[..3]}; fn initialize()->i64 {r.values.push(9);r.values.push(10);return 0;} var initialized=initialize();
var saved:const u16& = r.word;
export fn read_word()->i64 { r.word }
export fn saved_word()->i64 { saved }
export fn read_len()->i64 { r.values.len }
export fn churn(n:i64)->i64 { let local=R{1,n as u16,[7]}; local.word as i64+1 }
fn main() {}
