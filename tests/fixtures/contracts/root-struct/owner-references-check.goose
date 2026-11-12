// Owners pass by reference; a callee's effect on one component leaves a
// reference into another valid, through aliases, returned references,
// holders, optional references and branch selections.
root struct S { first: i64[>..<], second: i64[>..<], count: i64 = 0 }
struct Holder { s: S& }

fn head(s: S&) -> i64& { s.first[0] }
fn clear_other(s: S&) { s.second.clear(); s.count += 1; }
fn append(s: S&, x: i64) { s.first.push(x); }
fn same(s: S&) -> S& { s }
fn select(a: S&, b: S&, which: bool) -> S& { if which { a } else { b } }
fn from_holder(h: Holder&) -> S& { h.s }
fn exercise(s: S&) {
    let r .= head(s);
    clear_other(s);
    append(s, 12);
    print(r, " ", s.first.index_of(r), " ", s.first.len, " ", s.count);
}
fn main() {
    var a = S { [10], [20], .. };
    var b = S { [2], [30], .. };
    let alias = a;
    exercise(alias);
    let returned = same(a);
    print(returned.first.index_of(returned.first[0]));
    var holder = Holder { a };
    var refs: S&[2] = [a, b];
    var maybe: S&? = b;
    let one = from_holder(holder);
    clear_other(one);
    let chosen = select(a, b, false);
    let r .= head(chosen);
    clear_other(chosen);
    print(r, " ", refs[1].first[0]);
    if maybe { print(maybe.first[0]); }
    fn captured() { a.second.push(30); }
    captured();
}
