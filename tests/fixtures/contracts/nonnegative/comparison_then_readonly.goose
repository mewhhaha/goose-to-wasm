let big:u64=18446744073709551615;let small:u64=3;fn main(){let k=5;assert(big>k);let c:const i64& =k;var refs:(const i64&)[1]=[k];assert(c==5&&refs[0]==5);print("after readonly");}
