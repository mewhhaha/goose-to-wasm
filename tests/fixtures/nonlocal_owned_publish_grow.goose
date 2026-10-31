// Interrupted construction publishes the receiving split controls.
recursive fn enable_leave(n:i64){if n>0{enable_leave(n-1);return;}return[99] from enable;} fn enable()->i64[>..]{enable_leave(1);return[];}
var g:i64[>..]=[9];fn make<C>()->i64[>..]{return[C();16];}fn find(flag:bool)->i64{g=make(){if flag{return 7;}4};0}fn main(){print(enable());print(find(true)," ",g.len," ",g[0]);}
