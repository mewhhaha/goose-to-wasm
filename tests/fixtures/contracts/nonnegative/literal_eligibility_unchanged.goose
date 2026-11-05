let big:u64=18446744073709551615;let small:u64=3;fn width(x:u8)->i64{8}fn width(x:i64)->i64{64}fn main(){let k=300;let b:u8=1;assert(width(k+b)==64&&big>k);print("width unchanged");}
