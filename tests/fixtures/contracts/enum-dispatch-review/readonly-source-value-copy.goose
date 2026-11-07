enum Box { Left { n: i64 }, Right { n: i64 } }
fn amount(var x: Box.Left) -> i64 { x.n += 100; x.n }
fn amount(var x: Box.Right) -> i64 { x.n += 200; x.n }
fn read(x: const Box.Left&) -> i64 { x.n }
fn read(x: const Box.Right&) -> i64 { x.n }
fn main() {
    let a: const Box.. = Box.Left { n: 1 };
    var b: Box.. = Box.Right { n: 2 };
    var flag = true;
    print(amount(if flag { a } else { b }), " ", amount(if !flag { a } else { b }), " ", read(a), " ", read(b));
}
