// An integer operation over constructs whose values are all integer
// constants adapts as a whole to the type it meets, and is computed at that
// type; it is an i64 where nothing gives it one (upstream 71e5ade1, §6.1).
fn g(x: i32) -> i32 { x }
fn u(x: u8) -> u8 { x }
fn main() {
    var flags: bool[>..] = [true, false];
    let yes = flags[0];
    let no = flags[1];
    let p: i32 = (if yes {1} else {0}) + 1;
    var count: i32 = 0;
    count += (if yes {1} else {0}) + (if no {1} else {0});
    let q: i32 = (if yes {1} else {2}) * (if yes {3} else {4}) - 1;
    let m: u8 = (if no {1} else {2}) | 4;
    let w: i16 = (match p { 2 => 7, _ => 9 }) * 2;
    print(p, " ", count, " ", q, " ", m, " ", g((if yes {1} else {0}) - 3), " ", w);
    print(u((if yes {200} else {0}) + 100), " ", (if yes {200} else {0}) + 100);
}
