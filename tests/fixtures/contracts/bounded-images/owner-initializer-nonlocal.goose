struct Cell { value: i64 }
var cells: Cell[>..] = [Cell { 17 }];
struct Image { prefix: varint, link: Cell&<varint in cells>, tail: u8 }
fn read(p: Image&) -> i64 { p.link.value }
fn relay<F>(p: Image&) -> Cell& { assert(read(p)==17); F() }
fn trial(cancel: bool) -> i64 { let old=Image { 1, cells[0], 7 }; let next=Image { 2, relay(old) { if cancel { return 77 from trial; } &cells[0] }, 9 }; assert(old.tail==7 && next.tail==9); read(next) }
fn main() { assert(trial(true)==77 && trial(false)==17); print("image owner nested initializer exit ok"); }
