extern fn bench_input() -> i64;

enum Shape { Empty, Point { x: i64, y: i64 }, Samples { data: i64[3] } }
struct Box { code: i32, value: Shape }

fn make(n: i64) -> Shape {
    if n < 0 { return Shape.Empty; }
    if n % 2 == 0 { Shape.Point { n, n * 2 } }
    else { Shape.Samples { [n, n + 1, n + 2] } }
}
fn keep(s: Shape) -> Shape { s }
fn score(s: Shape) -> i64 {
    match s {
        Empty => 0,
        Point p => p.x + p.y,
        Samples s => s.data[0] + s.data[1] + s.data[2],
    }
}
fn via_ref(s: Shape&) -> i64 {
    match s { Empty => 10, Point, Samples => score(s) }
}
recursive fn recurse(n: i64) -> Shape {
    if n <= 0 { Shape.Point { 11, 22 } } else { keep(recurse(n - 1)) }
}
fn point(n: i64) -> Shape.Point { Shape.Point { n, n + 1 } }

fn main() {
    let n = bench_input();
    let a = make(n);
    let b = keep(a);
    print(a, " | ", b, " | ", score(b));
    let pair: Shape[2] = [a, make(n + 1)];
    print(pair);
    print(score(pair[0]) + score(pair[1]), " ", via_ref(a));
    var changing: Shape.. = Shape.Point { 5, 9 };
    match changing { Point &p => { p.x += 7; }, _ => {} }
    print(changing, " ", score(changing));
    let empty = default<Shape>();
    print(empty, " ", score(empty));
    print(recurse(7));
    let payload = point(n);
    let adapted: Shape = payload;
    print(payload.x, " ", payload.y, " ", adapted);
    print(Box { 7, make(n) });
}
