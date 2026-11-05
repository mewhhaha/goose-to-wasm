let K=3;fn main(){let before:const i64& = K;var flag=1;let n=match flag{1=>K,_=>5};let u:u64=18446744073709551615;assert(u>n);let after:const i64& = K;assert(before==after);print("readonly match");}
