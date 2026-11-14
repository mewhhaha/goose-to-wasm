 enum E{Data{flag:bool},None}
fn target()->E..{recursive fn leave(){return E.Data{true} from target;} leave();return E.None;}
fn main(){let e=target();}