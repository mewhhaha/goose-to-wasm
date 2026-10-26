extern fn bench_input() -> i64;
fn main() {
    let seed = bench_input();
    var values: i64[8] = [0; 8];
    for i in 8 { values[i] = (i + seed) * 3; }
    var total: i64 = 0;
    for x in values { total += x; }
    print(values[0], " ", values[7], " ", total);
    let view = values[2..6];
    var selected: i64 = 0;
    for x in view { selected += x; }
    print(view.len, " ", selected);
}
