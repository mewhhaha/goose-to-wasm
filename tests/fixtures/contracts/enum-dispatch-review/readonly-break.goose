enum Box { Left { n: i64 }, Right { n: i64 } }
fn touch(x: Box.Left&) { x.n += 1; }
fn touch(x: Box.Right&) { x.n += 1; }
fn main() {
    let a: const Box.. = Box.Left { n: 3 };
    var b: Box.. = Box.Right { n: 5 };
    var flag = true;
    touch(block { if flag { break a; } b });
}
