fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
var saved: i64[>..] = [7, 8, 9];
let view: const i64[:] = saved[..];
fn augment(v: i64) -> i64 { saved.append(make(v)); make(v).len }
let first = augment(10);
let second = augment(20);
fn main() {
    var total: i64 = 0;
    for i in 0..10000 { for value in make(1) { total += value; } }
    saved[0] = 70;
    print(view[0], " ", view[1], " ", view[2], " ", saved.len, " ", saved[3], " ", saved[8], " ", first + second, " ", total);
}
