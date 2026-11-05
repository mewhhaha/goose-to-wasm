reusable[] var a: i64[>..] = []; reusable[] var b: i64[>..] = [];
fn retarget(var p: i64[>..]&, q: i64[>..]&) { p .= q; let x=p.alloc_slice(2); x[0]=7; x[1]=8; }
fn main() { let old=b.alloc_slice(3); b.free_slice(old); retarget(a,b); assert(a.len==0 && b.len==3 && b[0]==7 && b[1]==8); print("rebound slice freelist ok"); }
