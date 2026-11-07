let K=7;fn take(x:u8)->u8{x}
fn choose(c:bool)->u8{take(block{if c{break 1;}break 255;})}
fn main(){print(take(block{break 1;})," ",take(block{break block{break 1;};})," ",take(block{break K;}));print(choose(true)," ",choose(false));}
