struct Cell<T> { tag:u8, value:T }
struct Wrap { prefix:u8, cells:Cell<u16>[2], suffix:u16 }
enum Choice { Packed { tag:u8, value:u16 }, Dynamic { values:u8[] } }

recursive fn leave_cells() { return [Cell<u16>{7,300},Cell<u16>{8,400}] from cells; }
recursive fn cells() -> Cell<u16>[u8] {
    var values:Cell<u16>[u8] = [Cell<u16>{1,2}]; leave_cells(); return values;
}
recursive fn leave_wrap() { return [Wrap {1,[Cell<u16>{2,300},Cell<u16>{3,400}],500}] from wraps; }
recursive fn wraps() -> Wrap[u16] { leave_wrap(); return []; }
recursive fn leave_rows() { return [[1,2],[3,4]] from rows; }
recursive fn rows() -> u16[2][u8] { leave_rows(); return []; }
recursive fn leave_variant() { return [Choice.Packed {9,0x3344}] from variants; }
recursive fn variants() -> Choice.Packed[u8] { leave_variant(); return []; }
fn main() {
    let a=cells(); print(a.len," ",a[0].tag as i64," ",a[0].value as i64," ",a[1].tag as i64," ",a[1].value as i64);
    let b=wraps(); print(b.len," ",b[0].prefix as i64," ",b[0].cells[0].tag as i64," ",b[0].cells[0].value as i64," ",b[0].cells[1].tag as i64," ",b[0].cells[1].value as i64," ",b[0].suffix as i64);
    let c=rows(); print(c.len," ",c[0][0] as i64," ",c[0][1] as i64," ",c[1][0] as i64," ",c[1][1] as i64);
    let d=variants(); print(d.len," ",d[0].tag as i64," ",d[0].value as i64);
}
