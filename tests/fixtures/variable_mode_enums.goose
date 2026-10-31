extern fn bench_input() -> i64;
enum Event<T> { Empty, Data { tag: u8, value: T, tail: i16[2] }, Pair { left: T, right: T } }
enum Defaulted { Value { number: i64 = 7, flag: u8 = 9 }, Empty }
enum Color { Red, Green, Blue }
enum Linked { Value { id: i64, point: i64&, view: const i64[:] } }
var defaults: Defaulted..;
var color: Color.. = Color.Blue;
var fallback = -100;
fn make(n: i64) -> Event<i64>.. { return Event<i64>.Data { 1, n, [2, 3] }; }
fn fixed(n: i64) -> Event<i64> { return Event<i64>.Pair { n, n + 1 }; }
fn variant(n: i64) -> Event<i64>.Data { return Event<i64>.Data { 4, n, [5, 6] }; }
fn score(e: const Event<i64>..&) -> i64 {
    return match e { Empty => 0, Data p => p.value + p.tail[0] + p.tail[1], Pair p => p.left + p.right };
}
fn bump(e: Event<i64>..&) -> i64 {
    return match e { Data &p => { p.tag += 1; p.value += 10; p.tail[0] += 20; p.value }, _ => -1 };
}
fn kept(e: Event<i64>..&) -> i64& { return match e { Data &p => p.value, _ => fallback }; }
fn changed(e: Event<i64>..) -> Event<i64>.. { bump(e); return e; }
fn aliases(n: i64) -> Event<i64>.., i64, Event<i64>.. {
    var e = make(n); return e, bump(e), e;
}
inline fn relay(n: i64) -> Event<i64>.. { var e = make(n); return e; }
recursive fn forward(n: i64) -> Event<i64>.. { if n <= 0 { return make(7); } return forward(n - 1); }
fn early(n: i64) -> Event<i64>.. {
    return Event<i64>.Data { 1, if n > 0 { return Event<i64>.Pair { 8, 9 }; } else { 2 }, [3, 4] };
}
fn mixed(n: i64) -> Event<i64>.., Event<i64>, Event<i64>.Data { return make(n), fixed(n + 1), variant(n + 2); }
fn adapted(n: i64) -> Event<i64>, Event<i64>.., Event<i64>.. { return mixed(n); }
fn external(e: Linked..) -> Linked.. {
    match e { Value &p => { p.id += 100; p.point += 1000; } } return e;
}
fn field(n: i64) -> i64 { print(n); return n; }
fn observe(a: const i64&, b: i64) -> i64 { return a + b; }
fn main() {
    let n = bench_input(); match defaults { Value p => print(p.number, " ", p.flag), _ => print(-1) }
    let original = make(n); let independent = changed(copy(original));
    let reference: i64& = kept(original);
    print(score(original), " ", score(independent), " ", reference);
    let a, marker, b = aliases(n); print(score(a), " ", marker, " ", score(b));
    match original { Data p => { bump(original); print(p.value, " ", p.tail[0], " ", score(original)); }, _ => {} }
    let converted: Event<i64> = relay(n + 30);
    let again: Event<i64>.. = converted;
    let from_fixed: Event<i64>.. = fixed(n + 40);
    let from_variant: Event<i64>.. = variant(n + 50);
    print(score(again), " ", score(from_fixed), " ", score(from_variant));
    let controlled: Event<i64>.. = if n > 0 { make(60) } else { Event<i64>.Empty {} };
    let looped: Event<i64>.. = loop { var local = make(70); break copy(local); };
    let exited = early(n); let recursive_value = forward(20);
    print(score(controlled), " ", score(looped), " ", score(exited), " ", score(recursive_value));
    print(match relay(n + 80) { Data p => p.value, _ => -1 }, " ", reference);
    let fa, vb, vc = adapted(n);
    let va: Event<i64>.. = fa;
    print(score(va), " ", score(vb), " ", score(vc), " ", match color { Blue => 3, _ => -1 });
    var number = n; var source = [n + 1, n + 2];
    let linked: Linked.. = Linked.Value { n, number, source[..] };
    let altered = external(copy(linked)); source[1] += 10;
    match linked { Value p => print(p.id, " ", p.point, " ", p.view[1]) }
    match altered { Value p => print(p.id, " ", p.point, " ", p.view[1]) }
    let ordered: Event<i64>.. = Event<i64>.Data { tag: field(1) as u8, value: field(2), tail: [field(3) as i16, field(4) as i16] };
    print(score(ordered));
    print(observe(match relay(n + 90) { Data &p => p.value, _ => fallback }, match relay(n + 100) { Data p => p.value, _ => -1 }));
}
