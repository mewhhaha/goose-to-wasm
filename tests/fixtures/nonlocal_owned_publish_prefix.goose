// Interrupted construction publishes the receiving split controls.
recursive fn enable_leave(n:i64){if n>0{enable_leave(n-1);return;}return[99] from enable;} fn enable()->i64[>..]{enable_leave(1);return[];}
struct F{id:i64,later:i64,after:i64,values:i64[>..]}var g=F{9,8,6,[7]};fn make<C>()->F{return F{1,C(),3,[4]};}fn find(flag:bool)->i64{g=make(){if flag{return 7;}2};0}fn main(){print(enable());print(find(true)," ",g.id," ",g.later," ",g.after," ",g.values.len," ",g.values[0]);}
