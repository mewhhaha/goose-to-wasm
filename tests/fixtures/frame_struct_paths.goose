extern fn bench_input() -> i64;
struct Packet { first: i64, second: i64, values: i64[>..] }
struct Pair { x: i64, y: i64 }
struct Envelope<T> { id: i64, values: T[>..] }
struct Linked { point: i64&?, values: i64[>..] }
var packet = Packet { 10, 20, [30] };
fn interrupted(n: i64) -> i64 {
    packet = Packet {
        if n == 1 { return 7; } else { 1 },
        if n == 2 { return 8; } else { 2 },
        [3]
    };
    return 0;
}
inline fn aliases(n: i64) -> Packet, i64, Packet {
    var local = Packet { n, n + 1, [n + 2] };
    return local, change(local), local;
}
fn change(p: Packet&) -> i64 {
    p.first += 10; p.second += 20; p.values[0] += 30; p.values.push(40); return p.first;
}
fn pair(n: i64) -> Envelope<Pair> { return Envelope<Pair> { n, [Pair { n + 1, n + 2 }] }; }
fn main() {
    let n = bench_input(); let exit = interrupted(n);
    print(exit, " ", packet.first, " ", packet.second, " ", packet.values);
    let a, marker, b = aliases(n);
    print(a.first, " ", a.second, " ", a.values, " ", marker, " ", b.first, " ", b.second, " ", b.values);
    let original = pair(n); let copied = copy(original); copied.values[0].x += 100;
    print(original.id, " ", original.values[0].x, " ", copied.values[0].x, " ", copied.values[0].y);
    var number = n; var link = Linked { number, [1] };
    link = Linked { values: [2] }; print(link.point == null, " ", link.values);
}
