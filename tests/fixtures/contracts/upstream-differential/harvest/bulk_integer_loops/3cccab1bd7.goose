var owned:u8[>..]=[];
var incoming:u32[:]; var outgoing:u32[:];
var first:u32[4]=[17,34,51,68]; var second:u32[4]=[81,82,83,84];
export fn clear() { let xs=outgoing; for i in xs.len { xs[i]=0; } }
export fn move(count:i64) { let src=incoming; let dst=outgoing; for i in count { dst[i]=src[i]; } }
export fn move_length() { let src=incoming; let dst=outgoing; for i in src.len { dst[i]=src[i]; } }
fn main() { owned.push(7); incoming=first[..]; outgoing=second[..]; }
