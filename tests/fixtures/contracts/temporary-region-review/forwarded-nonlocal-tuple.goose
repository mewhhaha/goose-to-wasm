fn escape(v: i64) -> i64[], i64[] {
    fn leave() { return [v, v + 1], [v + 2, v + 3] from escape; }
    for item in [1, 2] { leave(); }
    return [0], [0];
}
fn forward() -> i64[], i64[] { return escape(4); }
fn main() {
    var total: i64 = 0;
    for i in 0..10000 {
        let a, b = forward();
        for value in a { total += value; }
        for value in b { total += value; }
    }
    print(total);
}
