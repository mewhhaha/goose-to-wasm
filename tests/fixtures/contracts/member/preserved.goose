struct Fields { count: i64, push: i64 }
fn format(out: u8[>..]&, x: Fields) { format(out, "f", x.push); }
fn add_one(x: i64) -> i64 { x + 1 }
fn apply<F>(x: i64) -> i64 { F(x) }
fn append_builtin<push>(xs: i64[>..]&) { xs.push(7); }
fn main() {
    var xs: i64[>..] = [];
    append_builtin(xs, add_one); assert(xs.len == 1 && xs[0] == 7);
    var maybe: i64[>..]&? = xs; maybe.assert(); maybe.push(8);
    assert(xs.len == 2 && xs[1] == 8);
    assert(apply(3, add_one) == 4);
    let fields = Fields { 2, 3 }; var sum = 0;
    const for <Name, Access> in fields<Fields> { sum += fields.Access; }
    assert(sum == 5);
    var out: u8[>..] = []; out.format(fields, "!"); assert(out == "f3!");
    let n = 3; assert(n.str() == "3");
    print("member preservation passed");
}
