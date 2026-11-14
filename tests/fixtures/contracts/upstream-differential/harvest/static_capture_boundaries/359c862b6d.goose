 enum E{Data{number:f64},None}
fn target()->E..{recursive fn leave(){return E.Data{1.5} from target;} leave();return E.None;}
fn main(){let e=target();}