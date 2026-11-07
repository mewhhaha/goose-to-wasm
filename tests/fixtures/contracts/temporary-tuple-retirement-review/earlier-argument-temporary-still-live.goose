fn absorb(text: u8[:], n: i64) -> i64[], i64[] { return [text.len], [n]; }
recursive fn descend(n: i64) -> i64 {
    if n == 0 { return 0; }
    absorb(str(n), descend(n - 1));
    return n;
}
fn main() { print(descend(3)); }
