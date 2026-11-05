reusable var a: i64[>..] = [1]; reusable var b: i64[>..] = [2,3];
reusable[] var sa: i64[>..] = []; reusable[] var sb: i64[>..] = [];
var x: i64[>..] = [4]; var y: i64[>..] = [5,6];
var gp: i64[>..]& = a;
fn swap(var p: i64[>..]&, q: i64[>..]&) -> i64 { p .= q; p.len }
fn globals() { gp .= b; }
fn unused(var p: i64[>..]&) { p .= x; p.push(9); }
fn main() { assert(swap(a,b)==2); assert(swap(sa,sb)==0); assert(swap(x,y)==2); globals(); assert(gp.len==2); print("pool rebind kinds ok"); }
