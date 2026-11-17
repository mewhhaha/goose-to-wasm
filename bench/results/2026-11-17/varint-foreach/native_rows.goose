struct Row { id: i64, me: Row&<u32>, text: u8[] }
extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
fn main() {
    let n = bench_input();
    var rows: Row[>..] = [];
    let start = bench_clock();
    for i in n { rows.push(Row{i, self, "xy"}); }
    let filled = bench_clock();
    var sum: i64 = 0;
    for r in rows { sum += r.me.id; }
    let end = bench_clock();
    print(sum);
    print(filled - start);
    print(end - filled);
}
