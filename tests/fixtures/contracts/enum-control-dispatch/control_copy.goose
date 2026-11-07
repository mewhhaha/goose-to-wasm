enum Box { Left { n: i64 }, Right { n: i64 } }
fn bump(x: Box.Left&) -> i64 { x.n += 1; x.n }
fn bump(x: Box.Right&) -> i64 { x.n += 10; x.n }
fn main() { var a: Box.. = Box.Left { n: 1 }; var b: Box.. = Box.Right { n: 2 }; let copied = if true { a } else { b }; print(copied); }
