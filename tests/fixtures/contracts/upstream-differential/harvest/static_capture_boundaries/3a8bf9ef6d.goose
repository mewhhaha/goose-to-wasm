 enum E{Data{data:u8[..2]},None}
fn target()->E..{recursive fn leave(){return E.Data{[1]} from target;} leave();return E.None;}
fn main(){let e=target();}