enum Box { Left { n: i64 }, Right { n: i64 } }
fn bump(x: Box.Left&) -> i64 { x.n += 1; x.n }
fn bump(x: Box.Right&) -> i64 { x.n += 10; x.n }
fn echo<T>(x: Box.Left&, value: T) -> i64 { x.n + value as i64 }
fn echo<T>(x: Box.Right&, value: T) -> i64 { x.n + value as i64 }
fn rank(x: Box.Left&, value: i64) -> i64 { 100 + value }
fn rank(x: Box.Right&, value: i64) -> i64 { 100 + value }
fn rank(x: Box.Left&, value: u8) -> i64 { 200 + value }
fn rank(x: Box.Right&, value: u8) -> i64 { 200 + value }
fn main() {
 var a: Box.. = Box.Left { n: 1 }; var b: Box.. = Box.Right { n: 2 };
 print(bump(a), " ", bump(b));
 var narrow: u8 = 3;
 print(echo(if true { a } else { b }, narrow), " ", echo(if false { a } else { b }, 4));
 print(rank(if true { a } else { b }, 1), " ", rank(if false { a } else { b }, narrow));
}
