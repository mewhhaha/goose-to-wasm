struct Cell { tag:u8,value:u16 }
struct R { tag:u8,values:Cell[u32] }
fn target() -> R {
    var neighbor:i64[>..] = [987654321];
    recursive fn leave() { return R{7,[Cell{1,2};40000]} from target; }
    leave(); print(neighbor[0]); return R{0,[]};
}
fn main() { let value=target(); print(value.values.len); }