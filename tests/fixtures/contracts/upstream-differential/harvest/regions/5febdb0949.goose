var calls = 0;
fn many(n: i64) -> i64[>..], i64[2], i64[>..<] {
    calls++; return [n], [n + 1, n + 2], [n + 3];
}
export fn tick(n: i64) -> i64 {
    many(n); if calls != n + 1 { abort("wrong discarded call"); } return calls;
}
fn main() {}