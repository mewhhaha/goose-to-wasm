// A call's owned copy of an inner local's slice is stored into storage that
// outlives the local: an outer variable, a global and an outer array's
// element. The copy holds no references, so each store is valid.
fn copied(xs: const i64[:]) -> i64[] { return xs; }
var G: i64[>..] = [];
fn fill() { var xs: i64[] = [3, 4]; G = copied(xs[..]); }

fn main() {
    var outer: i64[>..] = [0, 0];
    { var xs: i64[] = [1, 2]; outer = copied(xs[..]); }
    print(outer);
    fill(); print(G);
    var rows: (i64[])[>..] = [];
    { var xs: i64[] = [5, 6]; rows.push(copied(xs[..])); }
    { var ys: i64[] = [7]; rows.push(copied(ys[..])); }
    print(rows);
}
