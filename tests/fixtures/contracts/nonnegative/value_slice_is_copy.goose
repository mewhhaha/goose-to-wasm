let big:u64=18446744073709551615;let small:u64=3;fn main(){let k=5;var xs:i64[2]=[k,6];let view=xs[..];view[0]=-1;assert(k==5&&big>k);print("value copy");}
