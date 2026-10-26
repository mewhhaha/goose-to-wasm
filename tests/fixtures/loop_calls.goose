extern fn bench_input() -> i64;

// This ordinary loop-bearing function should keep a real call boundary.
fn kernel(n: i64) -> i64 {
    var total = 0;
    for i in n { total += i * i + 1; }
    total
}

// Explicit inlining and function-value control/captures retain their rules.
inline fn forced(n: i64) -> i64 {
    var total = 0;
    for i in n { total += i; }
    total
}
fn each<F>(n: i64) { for i in n { F(i); } }
fn captured(n: i64) -> i64 {
    var total = 5;
    each(n) { total += it * 3; };
    total
}
fn finder(n: i64) -> i64 {
    each(n) { if it == 3 { return it + 100; } };
    -1
}
fn nested(n: i64) -> i64 {
    var total = 7;
    fn add(k: i64) { for i in k { total += i; } }
    add(n);
    total
}

fn main() {
    let n = bench_input();
    assert(n >= 0 && n <= 10);
    var sum = 0;
    for i in 3 { sum += kernel(n + i); }
    print(sum, " ", forced(n), " ", captured(n), " ", finder(n), " ", nested(n));
}
