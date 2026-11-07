fn take(x:u8)->u8{x}fn run(c:bool){print(take(block{if c{return;}break 1;}));}
fn main(){run(true);run(false);}
