// Components of each storage kind stand apart in one root owner: a struct
// with a growable tail, a record with a variable tail, a variable enum and
// fixed values beside resizable arrays. Each keeps its contents while the
// others grow and shrink, read through calls and a printed owner. Owners also
// link to each other through reference components.
struct Tail { flag: bool, values: i64[>..] }
struct Label { id: u16, text: u8[] }
enum Shape { Dot, Line { points: u8[] }, Box { w: i64, h: i64 } }
root struct Mix {
    tail: Tail,
    label: Label,
    shape: Shape..,
    items: i64[>..<] = [],
    total: i64 = 0
}
root struct Ring { next: Ring&?, values: i64[>..] }

fn grow(m: Mix&, n: i64) {
    for i in n { m.tail.values.push(i); m.items.push(i * 10); m.total += i; }
}
fn size(m: const Mix&) -> i64 {
    let extra = match m.shape { Line l => l.points.len, Box b => b.w * b.h, Dot => 100 };
    return m.tail.values.len + m.items.len + m.label.text.len + extra;
}
fn walk(r: Ring&, steps: i64) -> i64 {
    var at .= r; var total = 0;
    for i in steps {
        total += at.values[at.values.len - 1];
        let next = at.next;
        if next { at .= next; }
    }
    return total;
}
fn main() {
    var a = Mix { Tail { true, [1] }, Label { 7, "seven" }, Shape.Line { "ab" }, .. };
    var b = Mix { Tail { false, [] }, Label { 1, "one" }, Shape.Box { 2, 3 }, [4], 1 };
    let first .= a.tail.values[0];
    let item .= b.items[0];
    grow(a, 3);
    grow(b, 2);
    a.items.pop();
    print(first, " ", item, " ", size(a), " ", size(b));
    print(a);
    print(b);
    var x = Ring { null, [1] };
    var y = Ring { x, [2] };
    x.next .= y;
    y.values.push(5);
    print(walk(x, 5), " ", walk(y, 4));
}
