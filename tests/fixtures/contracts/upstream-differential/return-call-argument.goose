// A return moves the function's own local only into the returned value
// (§4.1, §7.3). A named function's argument inside it is a value-typed
// destination of its own, so a non-fixed local passed there needs copy().
fn count(a: i64[]) -> i64 { a.len }

fn once() -> i64 {
    var a: i64[] = [1, 2];
    return count(a);
}

fn main() { print(once()); }
