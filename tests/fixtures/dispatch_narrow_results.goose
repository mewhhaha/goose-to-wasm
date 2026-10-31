extern fn bench_input() -> i64;
enum Choice { One, Two }
recursive fn build(c: Choice.One, n: i64) -> u8[u8] {
    print("one"); var xs: u8[>..] = []; xs.resize(n, 7); return xs;
}
recursive fn build(c: Choice.Two, n: i64) -> u8[u8] {
    print("two"); var xs: u8[>..] = []; xs.resize(n, 8); return xs;
}
fn main() {
    let mode = bench_input(); let n = bench_input();
    let choice: Choice = if mode == 0 { Choice.One } else { Choice.Two };
    var xs: u8[>..] = []; xs.append(build(choice, n)); print(xs.len);
}
