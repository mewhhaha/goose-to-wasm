extern fn bench_input() -> i64;

var calls = 0;
fn observed(value: i64) -> i64 { calls++; return value; }

fn crc_byte(value: u32) -> u32 {
    var crc = 0xFFFFFFFF as! u32;
    crc ^= value;
    for bit in 8 {
        if crc & 1 != 0 { crc = (crc >> 1) ^ 0xEDB88320; }
        else { crc >>= 1; }
    }
    return crc ^ 0xFFFFFFFF;
}

fn main() {
    let seed = bench_input();
    let mode = bench_input();
    print(crc_byte(seed as! u32));
    var narrow = seed as! u8;
    for i in 8 { narrow += 31; }
    print(narrow);
    var dependent = 0;
    for i in 8 {
        if i < 3 { dependent += i + 1; }
        else { dependent ^= i * 7; }
    }
    print(dependent);
    var zero = 0;
    for i in 0 { zero += observed(i); }
    var nine = 0;
    for i in 9 { nine += i; }
    print(zero, " ", nine);
    var fallback = 0;
    for i in 8 {
        let value = i;
        fallback += observed(value);
        if i == 4 { continue; }
        if i == 6 { break; }
    }
    print(fallback, " ", calls);
    var storage = seed;
    var link: i64& = storage;
    for i in 8 { link ^= i; }
    print(storage);
    if mode == 1 {
        var checked = seed;
        for i in 8 { checked += 1; }
        print(checked);
    }
}
