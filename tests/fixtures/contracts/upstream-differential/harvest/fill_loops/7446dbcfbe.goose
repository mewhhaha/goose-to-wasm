var saved:u8[:];
var backing:u8[4]=[17,34,51,68];
export fn clear(input:u8) { let xs=saved; for i in xs.len { xs[i]=input; } }

fn main() { saved=backing[..];  }
