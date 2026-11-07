struct Point { x: i64 }
fn main() {
    reusable var ints = [];
    ints.push(7);
    let i = ints.alloc_index(8);
    reusable var points = [];
    let p .= points.alloc_ref(Point { 9 });
    print(ints[0], " ", ints[i], " ", p.x);
}
