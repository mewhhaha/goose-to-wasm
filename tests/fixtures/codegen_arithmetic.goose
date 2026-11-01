extern fn bench_input() -> i64;

var calls = 0;
fn observed(x: i64) -> i64 { calls++; return x; }

fn main() {
    let x = bench_input();
    let divisor = bench_input();
    print((x as! i8) % 64, " ", (x as! i16) % 16384, " ",
          (x as! i32) % 1073741824, " ", x % 4611686018427387904);
    print((x as! u8) % 128, " ", (x as! u16) % 32768, " ",
          (x as! u32) % 2147483648, " ", (x as! u64) % 0x8000000000000000);
    print(x % 1, " ", x % 2, " ", x % 8, " ", x % -8);
    var small = x as! i8;
    var wide = x;
    small %= 8;
    wide %= 8;
    print(small, " ", wide);
    print(observed(x) % 1, " ", calls);
    if x >= 0 && divisor > 0 {
        print(x / divisor, " ", x % divisor, " ", x >> 7);
        var changed = x;
        changed = -divisor - 1;
        print(changed % divisor);
    } else {
        print(x % divisor);
    }
}
