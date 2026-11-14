recursive fn leave(){return[64,-65] from target;}
recursive fn target()->varint[>..]{leave();return[];}
fn main(){let a=target();print(a);}