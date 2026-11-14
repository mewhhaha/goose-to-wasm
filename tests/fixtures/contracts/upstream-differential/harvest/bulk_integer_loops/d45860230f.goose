var incoming:u8[:]; var outgoing:u8[:];
var first:u8[4]=[17,34,51,68]; var second:u8[4]=[81,82,83,84];
export fn clear() { let xs=outgoing; for i in xs.len { xs[i]=0; } }
export fn move(count:i64) { let src=incoming; let dst=outgoing; for i in count { dst[i]=src[i]; } }
export fn move_length() { let src=incoming; let dst=outgoing; for i in src.len { dst[i]=src[i]; } }
fn main() { incoming=first[..]; outgoing=second[..]; }
