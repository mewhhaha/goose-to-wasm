extern fn bench_input() -> i64;
fn main() {
    let n = bench_input();
    var a: i8 = n as! i8;
    var b: u8 = n as! u8;
    let c: i16 = n as! i16;
    let d: u16 = n as! u16;
    let e: i32 = n as! i32;
    let f: u32 = n as! u32;
    print(a, " ", b, " ", c, " ", d, " ", e, " ", f);
    a += 1;
    b += 1;
    print(a, " ", b);
    print((a << 9), " ", (a >> 9), " ", (b >> 9));
}
