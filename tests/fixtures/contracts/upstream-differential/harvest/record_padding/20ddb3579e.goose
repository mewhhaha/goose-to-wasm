struct R{tag:u8,pad 2,word:u16,pad,values:u8[u8]} enum E{Data{tag:u8,pad 2,word:u16,pad,values:u8[u8]},Empty} var e:E..=E.Data{0x11,0x2233,[0x44,0x55]}; var payload:const E.Data& =match e{Data &p=>p,_=>abort("bad")};
var saved:const u16& = payload.word;
export fn read_word()->i64 { payload.word }
export fn saved_word()->i64 { saved }
export fn read_len()->i64 { payload.values.len }
export fn churn(n:i64)->i64 { let local=R{1,n as u16,[7]}; local.word as i64+1 }
fn main() {}
