import os;

struct Bag { tag: i64, values: i64[>..] }

fn made(n: i64) -> i64[>..] {
    var result: i64[>..] = [n, n + 1];
    result.push(n + 2);
    return result;
}
fn bag(n: i64) -> Bag { return Bag { tag: n, values: made(n) }; }
recursive fn chain(n: i64) -> i64[>..] {
    if n == 0 { return [7, 8]; }
    return chain(n - 1);
}
fn stop() { return [41, 42] from escaped; }
fn escaped() -> i64[>..] {
    var result: i64[>..] = [1, 2];
    stop();
    return result;
}
fn main() {
    var keep: i64[>..] = [3, 4];
    let first = &keep[0];
    for n in 0..20000 {
        let scratch: i64[>..] = [n; 1024];
        assert(scratch[0] == n && scratch.len == 1024);
    }
    for n in 0..4096 { keep.push(n); }
    assert(first == 3 && keep.len == 4098);
    keep.append(keep);
    assert(first == 3 && keep.len == 8196 && keep[4098] == 3);
    let value = bag(11);
    assert(value.tag == 11 && value.values[2] == 13);
    let chained = chain(100);
    assert(chained[0] == 7 && chained[1] == 8);
    var jumped = escaped();
    jumped.push(43);
    assert(jumped.len == 3 && jumped[0] == 41 && jumped[2] == 43);
    var shrinking: i64[>..<] = [5; 8192];
    shrinking.resize(1);
    assert(trim_memory());
    shrinking.resize(8192, 9);
    assert(shrinking[0] == 5 && shrinking[8191] == 9);
    print("ordinary regions ok");
}
