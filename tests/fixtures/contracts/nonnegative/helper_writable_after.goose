let big:u64=18446744073709551615;let small:u64=3;fn main(){let k=5;fn compare(){print(big>k);}compare();fn expose(){let r:i64& =k;print(r);}expose();}
