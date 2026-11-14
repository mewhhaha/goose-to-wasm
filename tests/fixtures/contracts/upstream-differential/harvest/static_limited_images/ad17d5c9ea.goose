var before:u8[8]="__zero_A";
var empty:u64[..0];
var after:u8[8]="__zero_B";
export fn count()->i64{empty.len+empty.cap} fn main(){print(before[0],after[0]);}