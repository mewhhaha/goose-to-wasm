let big:u64=18446744073709551615;let small:u64=3;fn run(c:bool){let a:i64=5;let k=if c{a}else{abort("unused")};assert(big>k);}fn main(){run(true);print("bottom branch");}
