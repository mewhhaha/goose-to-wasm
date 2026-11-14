enum Inner{A,B{n:u8}} enum E{Data{inner:Inner},None}
fn target()->E..{recursive fn leave(){return E.Data{Inner.A} from target;} leave();return E.None;}
fn main(){let e=target();}