reusable var a: i64[>..] = [1]; var plain: i64[>..] = [2,3];
fn main() { var p: i64[>..]&? = a; p .= plain; if p { assert(p.len==2); } p .= null; assert(p==null); print("optional pool proof stays plain"); }
