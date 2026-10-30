extern fn bench_input() -> i64;

enum Color { Red, Green, Blue }
enum Packet<T> { Empty, Data { tag: u8, value: T, tail: i16[3] }, Pair { left: T, right: T } }
enum Nested { A { x: Nested.C, y: Nested.B }, B { y: i64 }, C { z: Nested.B } }
enum Defaulted { Value { n: i64 = 7, flag: u8 = 9 }, Empty }
enum Flags { No, Empty {} }
enum Node { End, Link { value: i64, next: Node&? } }
enum Mixed { Small { x: i64 }, Big { values: i64[] } }
struct Holder { color: Color, packet: Packet<f64> }

var color: Color = Color.Green;
var packet: Packet<f64> = Packet<f64>.Data { 3, 2.5, [4, 5, 6] };

fn color_score(c: Color) -> i64 {
    match c { Red => 10, Green, Blue => 20 }
}
fn packet_score(p: Packet<f64>&) -> f64 {
    match p {
        Empty => 0.0,
        Data d => d.tag as f64 + d.value + d.tail[2] as f64,
        Pair d => d.left + d.right,
    }
}
fn small() -> Packet<i64>.Data { Packet<i64>.Data { 1, 2, [3, 4, 5] } }
recursive fn chain(node: Node&) -> i64 {
    match node { End => 0, Link p => {
        let next = p.next;
        if next { p.value + chain(next) } else { p.value }
    } }
}
fn main() {
    let n = bench_input();
    print(color_score(color), " ", packet_score(packet));
    var holder = Holder { Color.Red, Packet<f64>.Pair { n as f64, 0.5 } };
    print(color_score(holder.color), " ", packet_score(holder.packet));
    holder.color = Color.Blue;
    let none = default<Packet<f64>>();
    holder.packet = none;
    print(color_score(holder.color), " ", packet_score(holder.packet));
    var values: Color[3] = [Color.Red, Color.Green, Color.Blue];
    var total: i64 = 0;
    for c in values { total += color_score(c); }
    print(total);
    let nested: Nested = Nested.A { Nested.C { Nested.B { n } }, Nested.B { 2 } };
    match nested { A a => print(a.x.z.y + a.y.y), _ => print(-1) }
    let d = default<Defaulted>();
    match d { Value v => print(v.n, " ", v.flag), _ => print(-1) }
    let promoted: Defaulted = default<Defaulted.Empty>();
    print(match promoted { Empty => 77, _ => -1 });
    let flags: Flags = Flags.Empty {};
    print(match flags { Empty e => 8, _ => 9 });
    let empty = default<Color>();
    print(color_score(empty));
    let payload = small();
    print(payload.tag, " ", payload.value, " ", payload.tail[2]);
    var end: Node = Node.End;
    var middle: Node = Node.Link { n, &end };
    let head: Node = Node.Link { n + 1, &middle };
    print(chain(head));
    let standalone = Mixed.Small { n + 200 };
    print(standalone.x);
}
