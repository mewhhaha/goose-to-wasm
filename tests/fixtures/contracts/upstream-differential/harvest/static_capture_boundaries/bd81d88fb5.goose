struct Empty{} enum E{Data{empty:Empty},None}
fn target()->E..{recursive fn leave(){return E.Data{Empty{}} from target;} leave();return E.None;}
fn main(){let e=target();}