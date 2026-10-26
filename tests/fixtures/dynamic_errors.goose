extern fn bench_input() -> i64;
fn main() {
    let mode = bench_input();
    var values: i64[>..<] = [];
    if mode == 0 { values.pop(); }
    if mode == 1 { values.resize(-1, 7); }
    if mode == 2 { values.resize(3); }
    if mode == 3 { values.push(1); values.pop_n(2); }
    if mode == 4 {
        var limited: i64[..2] = [1, 2];
        limited.push(3);
    }
    if mode == 5 { values.resize(9223372036854775807, 1); }
    if mode == 6 { values.resize(100, 1); print(values[100]); }
    if mode == 7 { values.resize(100, 1); print(values[-1]); }
    if mode == 8 { values.resize(100, 1); print(values[70..101]); }
    if mode == 9 {
        var limited: i64[..] = [..2];
        limited = [1, 2, 3];
    }
    if mode == 10 { abort(str("failure ", mode)); }
    if mode == 11 {
        var bytes: u8[>..] = [];
        bytes.resize(300, 65);
        let compact: u8[u8] = copy(bytes);
        print(compact.len);
    }
    print("unexpected success");
}
