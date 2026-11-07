struct Ring { next: Ring&<u32>, value: i64 }
fn make() -> Ring[2] { [Ring { next: self, value: 3 }, Ring { next: self, value: 4 }] }
fn main() { var total: i64 = 0; for &ring in make() { total += ring.next.value; } print(total); }
