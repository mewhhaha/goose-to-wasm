fn invoke<F>(b:bool) { if b { F(); } }
recursive fn maker(x:u8) -> u8[u8] { return [7,8]; }
fn target(b:bool) -> u8[u8] {
    var values:u8[>..] = [1,2];
    invoke(b) { return maker(values.push(3)); }
    return values;
}
fn main() { let a=target(true); print(a.len); for x in a { print(x as i64); } }
