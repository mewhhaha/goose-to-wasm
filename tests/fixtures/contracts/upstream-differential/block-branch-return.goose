// An untyped block parameter takes a copy of the branch a construct selects,
// so a branch naming non-fixed storage is an error there (§4.1), except
// within the returned expression, where the function's own local moves
// (§7.3), as upstream accepts it.
fn chosen<F>(c: bool) -> i64 {
    var a: i64[] = [5];
    var b: i64[] = [6, 7];
    F(if c { a } else { b })
}

fn main() { print(chosen(true) { x => x[0] }, " ", chosen(false) { x => x.len }); }
