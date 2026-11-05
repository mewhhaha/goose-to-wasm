let big:u64=18446744073709551615;let small:u64=3;fn main(){let k=5;var refs:(const i64&)[1]=[k];let view=refs[..];assert(view[0]==5&&big>k);print("readonly slice");}
