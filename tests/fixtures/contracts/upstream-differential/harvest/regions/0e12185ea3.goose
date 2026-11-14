fn grown<F>() -> i64[>..] { return F(); }
export fn tick(n: i64) -> i64 {
    let named = grown() { [n, n + 1] };
    var calls = 0;
    for i in 100 {
        let value = grown() { calls++; [n + i] }[0];
        if value != n + i { abort("wrong fixed callback result"); }
    }
    if calls != 100 || named[0] != n || named[1] != n + 1 { abort("bad callback lifetime"); } return n + 1;
}
fn main() {}