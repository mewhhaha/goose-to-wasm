import std;
extern fn bench_input() -> i64;

var evaluations = 0;
fn once(value: i64) -> i64 { evaluations++; value }

fn main() {
    let x = bench_input();
    let u = x as! u64;
    print(x % 1, " ", x % 2, " ", x % 8, " ", x % 256, " ", x % 65536, " ", x % 4611686018427387904);
    print(u % 1, " ", u % 2, " ", u % 8, " ", u % 9223372036854775808);
    print(u / 1, " ", u / 2, " ", u / 8, " ", u / 9223372036854775808);
    let b = x as! i8;
    let s = x as! i16;
    let i = x as! i32;
    print(b % 8, " ", s % 256, " ", i % 65536);
    let b8: u8 = 129;
    let b16: u16 = 32769;
    let b32: u32 = 2147483649;
    let b64: u64 = 9223372036854775809;
    print(b8 << x, " ", b8 >> x, " ", b16 << x, " ", b16 >> x);
    print(b32 << x, " ", b32 >> x, " ", b64 << x, " ", b64 >> x);
    let signed8: i8 = -127;
    let signed32: i32 = -2147483647;
    print(signed8 >> x, " ", signed32 >> x);
    print(b << 9, " ", b >> -9, " ", i << 32, " ", u >> 65);
    print(once(x) % 8, " ", evaluations);
}
