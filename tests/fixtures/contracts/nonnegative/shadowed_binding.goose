let big:u64=18446744073709551615;fn main(){let k=5;assert(big>k);{let k=7;let r:i64& = k;r=-1;}assert(big>k);print("shadowed proof");}
