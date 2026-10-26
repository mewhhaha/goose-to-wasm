import std;
extern fn bench_input() -> i64;

var effects = 0;
fn side_effect(value: i64) -> i64 { effects++; value }
fn visit(value: i64&) { value += 3; effects++; }

fn select_integer(flag: bool, input: u32) -> u32 {
    var result = input;
    if flag { result = (result << 5) + result + 1; }
    else { result >>= 3; }
    result
}

fn constant_control(seed: i64) -> i64 {
    var result = seed;
    for i in 8 {
        if i == 2 { continue; }
        if i == 6 { break; }
        if result & 1 != 0 { result ^= i << 1; }
        else { result += i; }
    }
    result
}

fn main() {
    let input = bench_input();
    let flag = input & 1 != 0;
    print(select_integer(flag, input as! u32), " ", constant_control(input));

    // The condition changes the value read by both candidate expressions.
    var value = input;
    if { value++; effects++; value & 1 != 0 } { value ^= 85; } else { value ^= 170; }
    print(value, " ", effects);

    // Calls, checked casts, division and indexing must stay lazy.
    var lazy = 0;
    if flag { lazy = side_effect(5); } else { lazy = side_effect(7); }
    var divisor = 0;
    if flag { divisor = input; }
    var quotient = 7;
    if divisor != 0 { quotient = 123 / divisor; } else { quotient = 7; }
    var wide = 1000;
    var narrow: u8 = 0;
    if input == 1000 { narrow = wide as u8; } else { narrow = 7; }
    var values: i64[2] = [10, 20];
    var indexed = 9;
    if input == 1000 { indexed = values[input]; } else { indexed = 9; }
    print(lazy, " ", quotient, " ", narrow, " ", indexed, " ", effects);

    // A speculative addition would overflow in debug mode on input 1.
    var small: i8 = 127;
    if flag { small -= 1; } else { small += 1; }
    print(small);

    // Address-taking/calls, declarations and nested loops are deliberately
    // outside the small-loop transformation's accepted body shapes.
    var touched = 0;
    for i in 8 { visit(touched); }
    var sum = 0;
    for i in 8 { let copy = i; sum += copy; }
    var nested = 0;
    for i in 8 { for j in 8 { nested += i ^ j; } }
    print(touched, " ", sum, " ", nested, " ", effects);
}
