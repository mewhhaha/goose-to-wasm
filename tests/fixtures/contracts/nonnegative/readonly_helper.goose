let big:u64=18446744073709551615;let small:u64=3;fn main(){let k=5;fn compare(){assert(big>k);}compare();fn read(){let r:const i64& =k;assert(r==5);}read();print("readonly helper");}
