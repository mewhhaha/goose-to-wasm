extern fn bench_input() -> i64;
enum Choice { One, Two }
inline fn outer(n: i64) -> i64 {
    var total = 0;
    fn compute(c: Choice.One, value: i64&, extra: i64) -> i64 {
        total += n; value += extra; return value + total;
    }
    fn compute(c: Choice.Two, value: i64&, extra: i64) -> i64 {
        total += 2 * n; value += 2 * extra; return value + total;
    }
    let choice: Choice = if n % 2 == 0 { Choice.One } else { Choice.Two };
    var value = n; let result = compute(choice, value, 3);
    return result * 100 + total * 10 + value;
}
enum E { Leaf, Link { next: E..& } }
recursive fn build(e: E.Leaf) -> i64[u8] { return [7, 8]; }
recursive fn build(e: E.Link&) -> i64[u8] { return build(e.next); }
fn main() {
    print(outer(bench_input()));
    let leaf: E.. = E.Leaf; let link: E.. = E.Link { leaf };
    let wide: i64[u16] = build(link); print(wide);
}
