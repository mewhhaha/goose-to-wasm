import std;
extern fn bench_input() -> i64;

var effects = 0;
fn next_byte() -> u8 { effects++; effects as! u8 }

fn main() {
    let count = bench_input();
    assert(count >= 0 && count <= 32);
    let color = (count * 17 + 3) as! u8;
    var backing: u8[67] = [170; 67];
    let middle = backing[1..count + 1];
    fill(middle, color);
    var checksum = 0;
    for byte, i in backing { checksum += byte * (i + 1); }

    // The explicitly narrowed bound is 44, not the backing array's 300.
    var narrow: u8[300] = [1; 300];
    for i: u8 in narrow.len as! u8 { narrow[i] = 9; }
    var narrow_sum = 0;
    for byte in narrow { narrow_sum += byte; }

    var signed_bytes: i8[4] = [-1; 4];
    fill(signed_bytes, color as! i8);
    var signed_sum = 0;
    for byte in signed_bytes { signed_sum += byte; }

    // A fill-looking body with effects must evaluate its RHS per element.
    var writes: u8[5] = [0; 5];
    for i in writes.len { writes[i] = next_byte(); }
    var ordered = 0;
    for byte, i in writes { ordered += byte * (i + 1); }
    var partial: u8[5] = [9; 5];
    for i in partial.len - 1 { partial[i] = 6; }
    var partial_sum = 0;
    for byte in partial { partial_sum += byte; }
    print(checksum, " ", narrow_sum, " ", signed_sum, " ", ordered, " ", effects, " ", partial_sum);
}
