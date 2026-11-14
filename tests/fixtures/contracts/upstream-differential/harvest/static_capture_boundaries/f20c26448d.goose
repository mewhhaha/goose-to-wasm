var fallback:i64=0; enum E{Data{point:i64&},None}
fn target()->E..{recursive fn leave(){return E.Data{fallback} from target;} leave();return E.None;}
fn main(){let e=target();}