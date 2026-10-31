extern fn bench_input() -> i64;
struct Packet { tag: i64, data: i64[] }
struct Frame { tag: i64, data: i64[>..] }
enum Event { Empty, Data { tag: i64, data: i64[] } }
var calls = 0;
var shared: i64[>..] = [1, 2];
fn apply<F>(n: i64) -> i64[>..] { F(n) }
fn consume<F>(xs: i64[>..]) -> i64[>..] { F(copy(xs)) }
fn limited<F>(xs: i64[..]) -> i64 { F(copy(xs)) }
fn packet<F>(p: Packet) -> Packet { F(copy(p)) }
fn frame<F>(p: Frame) -> Frame { F(copy(p)) }
fn event<F>(e: Event..) -> Event.. { F(copy(e)) }
fn event_make<F>() -> Event.. { F() }
fn snapshot<F>(xs: i64[>..]&) -> i64 { F(copy(xs), block { xs[0] += 10; xs[0] }) }
fn size(xs: const i64[:]) -> i64 { xs.len * 100 + xs[0] }
fn viewed<F>() -> i64 { size(F()) }
fn touch() -> i64 { shared[0] = 99; 0 }
fn observe(xs: const i64[:], extra: i64) -> i64 { xs[0] + extra }
fn observed<F>() -> i64 { observe(F(), touch()) }
fn pair<F>() -> i64[>..], i64[>..] { return F(1), F(2); }
fn fixed_snapshot<F>(xs: i64[2]&) -> i64 { F(xs, block { xs[0] = 99; 0 }) }
fn main() {
    let n = bench_input();
    var source: i64[>..] = [n, n + 1];
    let changed = consume(copy(source)) { xs: i64[>..] =>
        calls++; xs[0] += 100; xs.push(7); copy(xs)
    };
    print(source, " ", changed, " ", calls);
    print(apply(n) { x => var xs: i64[>..] = [x + 2]; xs.push(x + 3); copy(xs) }, " ", calls);
    var cap: i64[..] = [..7]; cap.push(n);
    print(limited(copy(cap)) { xs: i64[..] => xs.push(9); xs.cap * 100 + xs.len }, " ", cap.len);
    let p = Packet { n, [n + 1, n + 2] };
    let q = packet(copy(p)) { item: Packet => item.tag += 10; item.data[0] += 20; copy(item) };
    print(p.tag, " ", p.data, " ", q.tag, " ", q.data);
    let f = Frame { n + 3, [n + 4] };
    let g = frame(copy(f)) { item: Frame => item.tag += 30; item.data.push(40); copy(item) };
    print(f.tag, " ", f.data, " ", g.tag, " ", g.data);
    let e: Event.. = Event.Data { n + 5, [n + 6] };
    let h: Event.. = event(copy(e)) { item: Event.. =>
        match item { Data &v => { v.data[0] += 50; }, Empty => {} };
        copy(item)
    };
    match e { Data &v => print(v.tag, " ", v.data), Empty => {} };
    match h { Data &v => print(v.tag, " ", v.data), Empty => {} };
    print(snapshot(source) { xs: i64[>..], later: i64 => xs[0] * 100 + later }, " ", source[0]);
    print(viewed() { var xs: i64[>..] = [n + 8, n + 9]; copy(xs) });
    print(observed() { shared }, " ", shared[0]);
    let left, right = pair() { x => var local: i64[>..] = [x]; copy(local) };
    print(left, " ", right);
    var fixed = [1, 2];
    print(fixed_snapshot(fixed) { xs: i64[2], later: i64 => xs[0] + later }, " ", fixed[0]);
    let direct: Event.. = event_make() { Event.Data { n + 70, [n + 71, n + 72] } };
    match direct { Data &v => print(v.tag, " ", v.data), Empty => {} };
}
