// The overloads take their variants by value. A dispatched call types the
// argument once for every overload, a direct call by the overload's own
// parameter: frames of one function whose arguments are of differing kinds.
enum Msg { Text { a: i64, keep: i64[>..]& }, Num { n: i64 } }
fn size(t: Msg.Text) -> i64 { t.a + t.keep.len }
fn size(n: Msg.Num) -> i64 { n.n }
fn total(xs: i64[>..]&, m: Msg&) -> i64 { xs.push(1); size(m) + xs.len }
fn main() {
    var a: i64[>..] = [1, 2, 3];
    var b: i64[>..] = [4];
    let m: Msg = Msg.Text { a: 5, keep: a };
    let n: Msg = Msg.Num { n: 7 };
    print(size(m), " ", size(n));
    let t = Msg.Text { a: 2, keep: b };
    let u = Msg.Num { n: 9 };
    print(size(t), " ", size(u));
    print(size(Msg.Text { a: 3, keep: a }), " ", size(Msg.Num { n: 1 }), " ", total(b, m), " ", total(a, n));
}
