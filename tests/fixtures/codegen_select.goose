extern fn bench_input() -> i64;

var calls = 0;
fn condition(choice: bool) -> bool { calls++; return choice; }

fn main() {
    let choice = bench_input() != 0;
    let x = bench_input();
    var crc = x as! u32;
    if condition(choice) {
        crc = (crc >> 1) ^ 0xEDB88320;
    } else {
        crc >>= 1;
    }
    print(crc, " ", calls);
    var narrow = x as! u8;
    if choice { narrow += 3; } else { narrow ^= 165; }
    print(narrow);
    var flag = choice;
    if choice { flag = x > 0; } else { flag = x == 0; }
    print(flag);
    var value = x;
    if choice { value = value ^ 85; } else { value ^= 170; }
    print(value);
}
