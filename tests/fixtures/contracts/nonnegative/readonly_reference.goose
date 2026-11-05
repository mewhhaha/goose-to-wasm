let big:u64=18446744073709551615;let small:u64=3;fn show(r:const i64&)->i64{r}fn main(){let k=5;let c:const i64& =k;assert(show(k)==5&&c==5&&small<k&&big>k&&!(big==k));print("readonly ref");}
