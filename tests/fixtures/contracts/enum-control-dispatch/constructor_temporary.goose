enum Box { Left { n: i64 }, Right { n: i64 } }
fn bump(x: Box.Left&) -> i64 { x.n += 1; x.n }
fn bump(x: Box.Right&) -> i64 { x.n += 10; x.n }
fn main() { print(bump(if true { Box.Left { n: 1 } } else { Box.Right { n: 2 } })); }
