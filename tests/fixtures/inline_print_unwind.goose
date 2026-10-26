extern fn bench_input() -> i64;

inline fn leave(x: i64, text: const u8[:]) -> i64 {
    print(text, block {
        if x > 0 { return x; }
        break 0;
    });
    return -1;
}

fn main() {
    let seed = bench_input();
    let text: u8[2048] = [65; 2048];
    var sum = 0;
    for i in 10000 { sum += leave(seed + i, text[..]); }
    print(sum);
}
