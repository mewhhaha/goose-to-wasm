enum E{Data{values:u8[u8]},Empty}
recursive fn make()->E.Data,i64{return E.Data{[7]},9;}
fn target()->E..,i64{recursive fn leave(){return make() from target;} leave();return E.Empty,0;}
fn main(){let e,n=target();print(n);}