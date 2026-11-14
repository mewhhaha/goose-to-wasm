struct Cell<T> { tag:u8,value:T }
enum E { Packed { tag:u8,value:u16 }, Other { values:u8[] } }
var neighbor:i64[>..] = [987654321];
recursive fn leave(depth:i64,value:i64) {
    if depth > 0 { leave(depth-1,value); return; }
    return [Cell<u16>{7,value as u16}],[E.Packed{8,(value+1) as u16}] from target;
}
recursive fn target(depth:i64,value:i64) -> Cell<u16>[u8],E.Packed[..] {
    if depth > 0 { return target(depth-1,value); }
    leave(3,value); return [],[];
}
export fn tick(n:i64) -> i64 {
    var left,right=target(12,n);
    if left.len != 1 || right.len != 1 || right.cap != 1 || left[0].value != n as u16 { abort("bad packed image escape"); }
    right.pop(); right.push(E.Packed{8,(n+1) as u16}); return right[0].value as i64;
}
fn main() {}