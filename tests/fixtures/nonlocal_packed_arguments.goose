struct Cell { tag:u8, value:u16 }
fn invoke<F>(b:bool) { if b { F(); } }
recursive fn maker(x:Cell,n:i64) -> Cell[u8] { return [x]; }
fn target(b:bool) -> Cell[u8] {
    var values:Cell[>..] = [Cell {7,0x1122}];
    invoke(b) { return maker(values[0],values.push(Cell {3,0x4455}).value as i64); }
    return values;
}
fn main() {
    let a=target(true); print(a.len);
    for i in a.len { if i < 2 { print(a[i].tag as i64," ",a[i].value as i64); } }
}
