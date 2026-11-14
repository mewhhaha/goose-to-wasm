// A declaration's statement temporaries end with it (§9.2) when what it
// declares holds no reference: a recursive call in a later statement keeps
// none of them, whether the declaration keeps a length, an element or a
// fixed struct read out of a call's owned array.
struct P { a: i64, b: i64 }
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
recursive fn points(n: i64) -> P[>..] { return [P { a: n, b: n + 1 }]; }
recursive fn lengths(n: i64) -> i64 {
    if n <= 0 { return 0; } let value = make(n).len; return lengths(n - 1) + value;
}
recursive fn elements(n: i64) -> i64 {
    if n <= 0 { return 0; } let value = make(n)[1]; return elements(n - 1) + value;
}
recursive fn fields(n: i64) -> i64 {
    if n <= 0 { return 0; } let p = points(n)[0]; return fields(n - 1) + p.b;
}
fn main() { print(lengths(50), " ", elements(50), " ", fields(50)); }
