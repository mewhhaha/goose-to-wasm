struct Pair { x: i64, y: i64 }
struct Borrowed { item: i64&, view: i64[:] }
var shared: i64[>..] = [1, 2];
var empty: i64[>..];
var alternate: i64[>..] = [50];
var destination: i64[>..]& = shared;
var produced = 0;
var scope_total = 0;
fn make_fixed(n: i64) -> i64[2] { produced++; return [n, n + 1]; }
fn mutate() -> i64 { shared.push(3); return 9; }
fn shared_owner() -> i64[>..]& { shared }
fn retarget() -> i64 { destination .= alternate; return 6; }
fn add(values: i64[>..]&, value: i64) { values.push(value); }
fn change(values: i64[>..<]&) -> i64 { values.push(7); return 9; }
fn count(values: i64[>..<]&) -> i64 { values.push(8); return 1; }
recursive fn append_recursive(values: i64[>..]&, n: i64) {
    if n <= 0 { return; }
    values.push(n); append_recursive(values, n - 1);
}
recursive fn scoped(n: i64) -> i64 {
    if n <= 0 { return 0; }
    let previous = scoped(n - 1);
    var values: i64[>..] = [n]; values.push(n + 1);
    return previous + values[0];
}
recursive fn released(n: i64) -> i64 {
    if n <= 0 { return 0; }
    if n % 2 == 0 {
        var values: i64[>..] = [n]; scope_total += values[0];
    } else {
        var values: i64[>..] = [n]; scope_total += values[0];
    }
    return released(n - 1) + 1;
}
fn main() {
    print(empty); empty.push(5); print(empty);
    var a: i64[>..] = [10];
    var b: i64[>..] = [];
    let first: i64& = a[0]; let old = a[..];
    for i in 5000 { add(a, i); b.push(-i); }
    first += 2;
    print(a.len, " ", b.len, " ", first, " ", old[0], " ", old.len, " ", a[5000], " ", b[4999]);
    let cloned: i64[>..] = a[..3]; cloned[0] = 77;
    print(cloned, " ", a[0]);
    let independent: i64[>..] = copy(a); independent[0] = 88;
    print(independent.len, " ", independent[0], " ", a[0]);
    var shrink: i64[>..<] = [1, 2];
    shrink.resize(5, 3); print(shrink, " ", shrink.pop());
    shrink.pop_n(2); shrink.clear();
    shrink.push(change(shrink)); shrink.pop_n(count(shrink));
    shrink.resize(4, change(shrink)); print(shrink);
    var overlap: i64[>..] = [2, 3]; overlap.append(overlap[..]); print(overlap);
    print(shared, " ", mutate(), " ", shared);
    shared_owner().push(4); append_recursive(shared, 3); print(shared);
    destination.push(retarget()); print(shared, " ", alternate);
    var text: u8[>..] = "abc"; text.push('!'); text.append("def"); print(text);
    var filled: i32[>..] = [6; 3]; print(filled);
    var zeros: i64[>..] = default<i64[3]>(); print(zeros);
    var returned: i64[>..] = make_fixed(30); print(returned, " ", produced);
    var pairs: Pair[>..] = [Pair { 1, 2 }]; pairs.push(Pair { 3, 4 });
    print(pairs[0].x, " ", pairs[1].y, " ", pairs.index_of(pairs[1]));
    var value = 10; var data: i64[2] = [20, 30];
    var holders: Borrowed[>..] = [Borrowed { value, data[..] }];
    let copied_holders: Borrowed[>..] = copy(holders);
    value = 40; data[0] = 50;
    print(copied_holders[0].item, " ", copied_holders[0].view[0]);
    var sum = 0;
    for i in 10000 {
        var local: i64[>..] = [i];
        if i % 2 == 0 { continue; }
        local.push(i + 1); sum += local[1];
    }
    print(sum, " ", scoped(20));
    print(released(20), " ", scope_total);
}
