extern fn bench_input() -> i64;
var calls: i64 = 0;
fn pair(n: i64) -> i64, i64 { calls++; return n + 1, n * 2; }
fn mutate(value: i64&) -> i64 { value += 5; return value; }
fn touch_text(bytes: u8[:]) -> i64 {
    for &byte in bytes { byte = 'z'; }
    print("inner");
    return 9;
}
fn main() {
    let n = bench_input();
    var value = n;
    var reference .= value;
    reference += 2;
    let a, b = pair(value);
    print(a, " ", b, " ", calls);
    let kind = match n { 0 => 10, 1 => 20, _ => 30 };
    let block_value = block { if n > 0 { break n + 7; } break 0; };
    let loop_value = loop { break n + 8; };
    print(kind, " ", block_value, " ", loop_value);
    var values: i64[4] = [1, 2, 3, 4];
    for &item in values { item += n; }
    var view = values[0..2];
    view = values[2..4];
    print(mutate(value), " ", value, " ", view[0], " ", view.len);
    var bytes: u8[3] = [97, 98, 99];
    print(bytes[..], " ", touch_text(bytes[..]));
}
