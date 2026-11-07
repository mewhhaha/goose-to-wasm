struct Row { id:i64, me:Row&<u32>, text:u8[] }
fn empty(p:Row[>..]&?)->bool { !p && p==null }
fn main(){assert(empty(null));print(empty(null));}
