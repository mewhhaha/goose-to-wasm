struct Cell {tag:u8,value:u16}
enum E {Data{values:Cell[u32]},Empty}
fn target()->E.. {
    var neighbor:i64[>..] = [987654321];
    recursive fn leave() {return E.Data{[Cell{1,2};40000]} from target;}
    leave();print(neighbor[0]);return E.Empty;
}
fn main() {let e=target();}