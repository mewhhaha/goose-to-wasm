extern fn bench_input() -> i64;

enum Value { Empty, Text { text: u8[] }, Numbers { values: i64[] } }
enum Limited { Empty, Values { values: i64[..5] } }
enum Node { Leaf { text: u8[] }, Pair { left: Node..&, right: Node..& } }

fn value(n: i64) -> Value.. {
    if n < 0 { return Value.Empty; }
    if n % 2 == 0 { Value.Text { str("value-", n) } }
    else { Value.Numbers { [n, n + 1, n + 2] } }
}
fn score(v: Value..&) -> i64 {
    match v { Empty => 0, Text t => t.text.len, Numbers a => a.values[0] + a.values[2] }
}
fn payload(n: i64) -> Value.Text { Value.Text { str("payload-", n) } }
fn early(n: i64) -> Value.. {
    let a = value(n);
    if n % 2 == 0 { return copy(a); }
    let b = value(n + 1);
    return copy(b);
}
recursive fn tree_score(n: Node..&) -> i64 {
    match n { Leaf l => l.text.len, Pair p => tree_score(p.left) + tree_score(p.right) }
}

fn main() {
    let n = bench_input();
    let a = value(n);
    let b = copy(a);
    print(a, " | ", b, " | ", score(b));
    let p = payload(n);
    let adapted: Value.. = copy(p);
    print(p, " | ", adapted);

    var limited: Limited = Limited.Values { [2, 3] };
    let saved = copy(limited);
    limited = Limited.Empty;
    print(saved, " | ", limited);
    limited = Limited.Values { [7, 8, 9] };
    print(limited);

    var nodes: Node..[>..] = [];
    let left = nodes.push(Node.Leaf { "left" });
    let right = nodes.push(Node.Leaf { "right" });
    let root = nodes.push(Node.Pair { left, right });
    for i in 200 { nodes.push(Node.Leaf { str(i) }); }
    print(tree_score(root));

    var total = 0;
    for i in 10000 {
        let one = early(i);
        if i % 3 == 0 { continue; }
        total += score(one);
    }
    print(total);
    let empty = default<Limited>();
    print(empty);
}
