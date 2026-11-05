struct Cell { value: i64 }
var cells: Cell[>..] = [];
var global: Cell&<varint in cells>? = null;
var missing: Cell&<varint>?;
fn identity<T>(r: T) -> T { r }
fn pair<T>(r: T) -> T, T { return r, r; }
recursive fn relay(r: Cell&, n: i64) -> Cell& {
    if n == 0 { return r; }
    return relay(r, n - 1);
}
fn captured(r: Cell&<varint in cells>) -> Cell& {
    fn inner() -> Cell& { r }
    inner()
}
fn optional(r: Cell&<varint in cells>?) -> i64 {
    if r { return r.value; }
    return -1;
}
enum Mode { A, B }
fn dispatch(mode: Mode.A, r: Cell&<varint in cells>) -> Cell& { r }
fn dispatch(mode: Mode.B, r: Cell&<varint in cells>) -> Cell& { r }
fn main() {
    for i in 40 { cells.push(Cell { value: 100 + i }); }
    assert(global == null && missing == null);
    var value: Cell&<varint in cells>? = cells[18];
    assert(optional(value) == 118 && &value .== &cells[18]);
    value .= cells[0];
    assert(optional(value) == 100 && &value .== &cells[0]);
    value .= null; assert(value == null);
    value .= cells[17]; global .= value;
    assert(optional(global) == 117 && optional(null) == -1);
    let copied: Cell&<varint in cells> = identity<Cell&<varint in cells>>(cells[19]);
    assert(copied.value == 119 && relay(copied, 5) .== &cells[19]);
    assert(captured(copied) .== &cells[19]);
    let a, b .= pair<Cell&<varint in cells>>(cells[20]);
    assert(a .== &cells[20] && b .== a);
    let absent: Cell&? = default<Cell&<varint>?>(); assert(absent == null);
    for mode in [Mode.A, Mode.B] { assert(dispatch(mode, copied) .== &cells[19]); }
    print("scalar varint relative ABI ok");
}
