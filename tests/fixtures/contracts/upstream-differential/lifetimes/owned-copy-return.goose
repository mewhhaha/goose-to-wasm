// An owned array copied out of a slice holds no references, so returning
// it straight from a call is not an escape, whatever the slice viewed: a
// local, a temporary or a parameter. The same holds for a struct field, a
// tuple component, an if's branches, a block's tail and a return from.
struct Owned { v: i64[] }
struct Mixed { v: i64[], r: const i64[:] }
let G: i64[] = [5, 6];
fn copied(xs: const i64[:]) -> i64[] { return xs; }
fn wrapped(xs: const i64[:]) -> Owned { return Owned { xs }; }
fn mixed(xs: const i64[:]) -> Mixed { return Mixed { v: xs, r: G[..] }; }
fn paired(xs: const i64[:]) -> i64[], i64 { return xs, xs.len; }
recursive fn grown(xs: const i64[:]) -> i64[>..] { return xs; }

fn direct() -> i64[] { var xs: i64[] = [7, 8]; return copied(xs[..]); }
fn whole() -> i64[] { var xs: i64[] = [7, 9]; return copied(xs); }
fn tail() -> i64[] { var xs: i64[] = [7, 10]; copied(xs[..]) }
fn literal() -> i64[] { return copied([7, 11]); }
fn field() -> Owned { var xs: i64[] = [7, 12]; return wrapped(xs[..]); }
fn holder() -> Mixed { var xs: i64[] = [7, 13]; return mixed(xs[..]); }
fn tuple() -> i64[], i64 { var xs: i64[] = [7, 14, 15]; return paired(xs[..]); }
fn chosen(c: bool) -> i64[] {
    var xs: i64[] = [7, 16]; var ys: i64[] = [17];
    return if c { copied(xs[..]) } else { copied(ys[..]) };
}
fn far() -> i64[>..] {
    var xs: i64[>..] = [7, 18];
    recursive fn leave() { return grown(xs[..]) from far; }
    leave(); return [];
}

fn main() {
    print(direct(), " ", whole(), " ", tail(), " ", literal());
    print(field().v);
    let h = holder(); print(h.v, " ", h.r);
    let t, n = tuple(); print(t, " ", n);
    print(chosen(true), " ", chosen(false), " ", far());
}
