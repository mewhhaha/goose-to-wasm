enum Box { Left { n: i64 }, Right { n: i64 } }
fn amount(x: Box.Left) -> i64 { x.n }
fn amount(x: Box.Right) -> i64 { x.n }
fn make(left: bool) -> Box.. { if left { return Box.Left { n: 5 }; } Box.Right { n: 6 } }
fn main() {
 var a: Box.. = Box.Left { n: 1 }; var b: Box.. = Box.Right { n: 2 };
 print(amount(if true { a } else { b }));
 var c: Box = Box.Left { n: 3 }; var d: Box = Box.Right { n: 4 };
 print(amount(if false { c } else { d }));
 print(amount(if true { make(true) } else { make(false) }));
}
