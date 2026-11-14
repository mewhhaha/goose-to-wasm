var calls = 0;
recursive fn pair(n: i64) -> i64, i64[>..], i64[>..<] {
    calls++; return n, [n + 1], [n + 2];
}
fn single(n: i64) -> i64[>..] { calls++; return [n]; }
recursive fn descend(n: i64) -> i64 {
    if n <= 0 { return 0; }
    pair(descend(n - 1)); single(descend(n - 1)); return n;
}
export fn tick(n: i64) -> i64 {
    calls = 0;
    if descend(5) != 5 || calls != 62 { abort("wrong recursive result"); } return n + 1;
}
fn main() {}