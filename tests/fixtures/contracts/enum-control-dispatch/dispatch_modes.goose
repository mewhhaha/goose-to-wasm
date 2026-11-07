enum Box { Left { n: i64 }, Right { n: i64 } }
fn bump(x: Box.Left&) -> i64 { x.n += 1; x.n }
fn bump(x: Box.Right&) -> i64 { x.n += 10; x.n }
var calls: i64 = 0;
fn condition() -> bool { calls += 1; true }
fn main() {
 var a: Box.. = Box.Left { n: 1 };
 var b: Box.. = Box.Right { n: 20 };
 print(bump(if condition() { a } else { b }));
 print(bump(match 1 { 1 => b, _ => a }));
 print(bump(block { if calls == 1 { break a; } b }));
 print(bump(loop { break b; }));
 print(bump({ a }), " ", calls);
}
