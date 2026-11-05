struct Cell { value: i64 }
var cells: Cell[>..] = [];
fn later() -> i64 { print("later argument ran");0 }
fn take(cell: Cell&<u8 in cells>, value: i64) { print(cell.value + value); }
fn main() {
    for i in 33 { cells.push(Cell { value: i }); }
    take(cells[32], later());
}
