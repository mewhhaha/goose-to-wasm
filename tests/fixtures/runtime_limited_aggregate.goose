extern fn bench_input() -> i64;
struct Pair { x: i64, y: i64 }
fn make(n: i64) -> Pair[..] {
    var xs: Pair[..] = [..4]; xs.push(Pair { n, n + 1 }); xs.push(Pair { n + 2, n + 3 }); return xs;
}
fn changed(xs: Pair[..]) -> Pair[..] { xs[0].x += 10; xs.push(Pair { 20, 21 }); return xs; }
fn main() {
    let n = bench_input(); var xs = make(n);
    let first: const Pair& = xs[0];
    let copied = changed(copy(xs)); xs.push(Pair { 30, 31 });
    let last = xs.pop(); xs.push(Pair { 40, 41 });
    print(first.x, " ", xs[0].y, " ", last.x, " ", xs[2].x, " ", xs.cap);
    print(copied[0].x, " ", copied.len, " ", copied.cap, " ", xs.len);
    xs = xs[1..]; print(xs[0].x, " ", xs[1].x, " ", xs.len, " ", xs.cap);
}
