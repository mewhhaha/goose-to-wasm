extern fn bench_input() -> i64;
struct Holder { item: i64&, view: i64[:] }
var numbers: i64[4] = [7, 8, 9, 10];
var pair: i64[2] = [20, 21];
var scalar = 11;
var holders: Holder[1] = [Holder { scalar, numbers[..2] }];
var view: i64[:] = numbers[..2];
fn fixed(n: i64) -> i64[2], i64 { return [n, n + 1], n + 2; }
fn promoted(n: i64) -> i64[>..], i64 { return fixed(n); }
fn sources(n: i64) -> i64[:], i64[2], i64[>..<], i64[2]& {
    return numbers[..2], [n, n + 1], [n + 2], pair;
}
fn many(n: i64) -> i64[>..], i64[>..], i64[>..], i64[>..] { return sources(n); }
fn held() -> Holder[:], i64 { return holders[..], 5; }
fn adapted_holder() -> Holder[>..], i64 { return held(); }
fn change_view() -> i64 { view = numbers[1..3]; return 6; }
fn ref_view() -> i64[:]& , i64 { return view, change_view(); }
fn adapted_ref_view() -> i64[>..], i64 { return ref_view(); }
fn mutate() -> i64 { numbers[0] = 30; return 9; }
fn ordered() -> i64[:], i64 { return numbers[..2], mutate(); }
fn adapted_ordered() -> i64[>..], i64 { return ordered(); }
fn main() {
    let n = bench_input();
    let p, marker = promoted(n); print(p, " ", marker);
    let a, b, c, d = many(n); print(a, " ", b, " ", c, " ", d);
    numbers[0] = 77; pair[0] = 88; a[0] += 100;
    print(a, " ", d, " ", numbers[0], " ", pair[0]);
    let h, tag = adapted_holder(); scalar = 44; numbers[0] = 55;
    print(h[0].item, " ", h[0].view[0], " ", tag);
    let from_ref, ref_tag = adapted_ref_view(); numbers[1] = 67;
    print(from_ref, " ", ref_tag, " ", numbers[1]);
    let after, order = adapted_ordered(); print(after, " ", order);
}
