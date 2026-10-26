extern fn bench_input() -> i64;
fn score(n: i64) -> i64 {
    var total: i64 = 0;
    for i in n {
        if i % 3 == 1 { continue; }
        if i > 11 { break; }
        total += i * i;
    }
    var countdown = n;
    while countdown > 0 {
        total += countdown;
        countdown--;
    }
    if total > 100 { return total - 100; }
    return total + 100;
}
fn main() { print(score(bench_input())); }
