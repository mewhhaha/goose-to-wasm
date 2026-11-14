fn target() -> u8[u32] {
    var neighbor:i64[>..] = [987654321];
    recursive fn leave() { return [1 as u8;100000] from target; }
    leave(); print(neighbor[0]); return [];
}
fn main() { let value=target(); print(value.len); }