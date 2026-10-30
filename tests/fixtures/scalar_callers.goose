fn base(x: i64) -> i64 { x + 1 }
fn left(x: i64) -> i64 { base(x) * 3 }
fn right(x: i64) -> i64 { base(x) + 2 }
fn diamond(x: i64) -> i64 { left(x) + right(x) }
fn subtract(x: i64, y: i64) -> i64 { x - y }
fn argument_order(x: i64, y: i64) -> i64 { subtract(x, y) + subtract(y, x) }
fn higher(x: i64) -> i64 { diamond(x) + base(x) }
fn compose(x: i64) -> i64 { left(x) * right(x) }
fn main() {
    print(diamond(3), " ", argument_order(9, 2), " ", higher(3), " ", compose(3));
}
