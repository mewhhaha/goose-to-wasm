struct R {tag:u8,word:u16,values:u8[u8]} enum E {Data{tag:u8,word:u16,values:u8[u8]},Other{n:i64}} var r=E.Data{0x11,0x2233,[0x44,0x55]};
var saved:const u16& = r.word;
export fn read_word()->i64 { r.word }
export fn saved_word()->i64 { saved }
export fn read_len()->i64 { r.values.len }
export fn churn(n:i64)->i64 { let local=R{1,n as u16,[7]}; local.word as i64+1 }
fn main() {}
