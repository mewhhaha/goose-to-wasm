var global: i64[] = [7, 8];
fn make(n: i64) -> i64[] { return [n, n + 1]; }
fn change(xs: i64[]) -> i64[] { xs[0] += 10; return xs; }
fn grow(xs: i64[>..]&) -> i64 { xs[0] += 10; xs.push(99); return xs.len; }
fn named(n: i64) -> i64[], i64, i64[] {
    var xs: i64[>..] = [n]; return xs, grow(xs), xs;
}
recursive fn forward(n: i64) -> i64[] {
    if n <= 0 { return [20, 21]; } return forward(n - 1);
}
fn main() {
    let xs = make(3); let ys = change(copy(xs)); print(xs, " ", ys, " ", global);
    let a, n, b = named(4); print(a, " ", n, " ", b);
    print(forward(20), " ", make(7)[1]);
    let text: u8[] = "hello"; print(text);
    let chosen: i64[] = if true { [8, 9] } else { [] }; print(chosen);
    var sum = 0; for x in make(4) { sum += x; } print(sum);
    let explicit: i64[u32] = make(5); let empty: i64[] = [];
    let fixed: i64[2] = [30, 31]; let from_slice: i64[] = fixed[..];
    let from_variable: i64[>..] = copy(explicit);
    from_variable.push(7); print(explicit, " ", empty.len, " ", from_slice, " ", from_variable);
    let broken: i64[] = loop { let item: i64[] = [40]; break copy(item); }; print(broken);
}
