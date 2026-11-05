fn value(c:bool)->i64{var a=1;var b=2;let r:i64?;if c{r .= &a;}else{r .= &b;}if r{return r;}return 0;}fn main(){print(value(true)," ",value(false));}
