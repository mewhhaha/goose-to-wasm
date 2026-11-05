let big:u64=18446744073709551615;let small:u64=3;fn run(k:i64){assert(big>(k as u64));}fn main(){run(5);print("explicit conversion");}
