reusable var a: i64[>..] = [1,2,3]; reusable var b: i64[>..] = [4,5,6];
fn retarget(var p: i64[>..]&, q: i64[>..]&) -> i64 { p .= q; p.alloc_index(9) }
fn main() { b.free(1); assert(retarget(a,b)==1 && b[1]==9 && a[1]==2); print("rebound slot freelist ok"); }
