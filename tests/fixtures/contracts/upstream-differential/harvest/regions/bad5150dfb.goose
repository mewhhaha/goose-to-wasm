struct Cell { tag:u8,value:u16 }
fn target() -> Cell[u32] {
    var neighbor:i64[>..] = [987654321];
    recursive fn leave() { return [Cell{1,2};40000] from target; }
    leave(); print(neighbor[0]); return [];
}
fn main() { let value=target(); print(value.len); }