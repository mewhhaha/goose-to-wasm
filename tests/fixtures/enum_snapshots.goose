extern fn bench_input() -> i64;
enum Choice { None, Data { x: i64, ys: i64[2] } }
var shared: Choice = Choice.Data { 11, [22, 33] };
var ticks: i64 = 0;
fn tick(n: i64) -> i64 { ticks = ticks * 10 + n; return n; }
fn mutate() -> i64 { shared = Choice.None; return 99; }
fn total(c: Choice) -> i64 {
    match c { None => -1, Data p => p.x + p.ys[0] + p.ys[1] }
}
fn arguments(c: Choice, ignored: i64) -> i64 { total(c) }
fn results() -> Choice, i64 { return shared, mutate(); }
fn main() {
    let n = bench_input();
    let copied = shared;
    print(arguments(shared, mutate()), " ", total(shared), " ", total(copied));
    shared = Choice.Data { n, [n + 1, n + 2] };
    match shared {
        Data p => {
            let ignored = mutate();
            print(p.x, " ", p.ys[0], " ", p.ys[1], " ", total(shared));
        },
        None => print(-2),
    }
    shared = Choice.Data { 4, [5, 6] };
    let first, second = results();
    print(total(first), " ", second, " ", total(shared));
    let ordered: Choice = Choice.Data { tick(1), [tick(2), tick(3)] };
    print(total(ordered), " ", ticks);
    shared = ordered;
    let independent = copy(shared);
    shared = Choice.None;
    print(total(independent));
}
