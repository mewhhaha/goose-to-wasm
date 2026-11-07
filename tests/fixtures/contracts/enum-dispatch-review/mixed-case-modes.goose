enum Box { Left { n: i64 }, Right { n: i64 } }
fn use(x: Box.Left) -> i64 { x.n }
fn use(x: Box.Right&) -> i64 { x.n += 20; x.n }
fn main() {
    var a: Box.. = Box.Left { n: 3 };
    var b: Box.. = Box.Right { n: 5 };
    var flag = true;
    print(use(if flag { a } else { b }), " ", use(if !flag { a } else { b }));
    print(use(a), " ", use(b));
}
