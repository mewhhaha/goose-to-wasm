let big:u64=18446744073709551615;let small:u64=3;fn run(c:bool){let k=if c{5}else{6};assert(big>k);}fn main(){run(true);run(false);print("constant branches");}
