enum Box { Left { n: i64 }, Right { n: i64 } }
fn read(x: const Box.Left&) -> i64 { x.n }
fn read(x: const Box.Right&) -> i64 { x.n }
fn main() { let a: const Box.. = Box.Left { n: 1 }; var b: Box.. = Box.Right { n: 2 }; print(read(if true { a } else { b })); }
