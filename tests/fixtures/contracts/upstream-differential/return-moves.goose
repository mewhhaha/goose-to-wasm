// What a return still moves (§4.1, §7.3), as upstream accepts it: the local
// itself, a field or element of the value it constructs, a branch it selects,
// and, within the returned expression, a block's argument, even under an
// operand or a named function's argument.
struct Pair { n: i64, xs: i64[] }

fn twice(n: i64) -> i64 { n * 2 }
fn whole() -> i64[] { var a: i64[] = [1, 2]; return a; }
fn field() -> Pair { var a: i64[] = [1, 2, 3]; return Pair { 1, a }; }
fn element() -> i64[][>..] { var a: i64[] = [4]; return [a]; }
fn branch(c: bool) -> i64[] { var a: i64[] = [1]; var b: i64[] = [1, 2]; return if c { a } else { b }; }
fn operand<F>() -> i64 { var a: i64[] = [1, 2]; return 1 + F(a); }
fn nested<F>() -> i64 { var a: i64[] = [1, 2, 3]; twice(F(a)) }

fn main() {
    print(whole().len, " ", field().xs.len, " ", element().len, " ", branch(false).len);
    print(operand() { a: i64[] => a.len }, " ", nested() { a: i64[] => a.len });
}
