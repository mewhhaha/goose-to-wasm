var calls = 0;
fn many(n: i64) -> i64[>..], i64, i64[2], i64[>..<] {
    calls++; return [n], n + 1, [n + 2, n + 3], [n + 4];
}
fn single(n: i64) -> i64[>..] { return [n]; }
recursive fn recurse(n: i64) -> i64 {
    if n <= 0 { return 0; }
    many(recurse(n - 1)); single(recurse(n - 1)); return n;
}
fn main() { many(1); many(2); print(calls); print(recurse(4), " ", calls); }
