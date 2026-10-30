fn arithmetic(x: i64, y: i64) -> i64 { (x + y) * 3 - x / y + x % y }
fn bits(x: i64, y: i64) -> i64 { ((x << 2) ^ (y >> 1)) & 255 }
fn logic(x: i64, y: i64, flag: bool) -> bool { (!(x < y) && x != y) || flag }
fn narrow(x: i8, y: i8) -> i8 { x + y }
fn shift(x: u8, n: i64) -> u8 { x >> n }
fn mixed(x: i64, y: f32) -> f32 { x + y * 0.5 }
fn choose(flag: bool, x: i32, y: i32) -> i32 { if flag { x } else if x < y { y } else { x } }
fn early(x: i64) -> i64 { guard x >= 0 else { return -x; } x + 1 }
fn zero() -> f64 { -0.0 }
fn float_choice(flag: bool, x: f32) -> f32 { if flag { x + 0.25 } else { -x } }
fn main() {
    print(arithmetic(17, 5), " ", bits(17, 5), " ", logic(17, 5, false));
    print(narrow(12, 13), " ", shift(255, 2), " ", mixed(3, 2.5));
    print(choose(true, 7, 9), " ", early(5), " ", early(-7), " ", choose(false, 7, 9));
    print(1.0 / zero(), " ", float_choice(true, 1.0), " ", float_choice(false, 2.0));
}
