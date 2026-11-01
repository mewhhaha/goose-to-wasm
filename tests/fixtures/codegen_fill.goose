extern fn bench_input() -> i64;

var calls = 0;
fn observed() -> u8 { calls++; return 85; }
fn bytes(xs: u8[:], value: u8) { for i in xs.len { xs[i] = value; } }
fn signed(xs: i8[:], value: i8) { for i in xs.len { xs[i] = value; } }
fn effects(xs: u8[:]) { for i in xs.len { xs[i] = observed(); } }
fn linked(xs: u8[:], value: u8&) { for i in xs.len { xs[i] = value; } }
fn varying(xs: u8[:], value: u8) {
    var next = value;
    for i in xs.len { xs[i] = next; next += 1; }
}
fn rebound(first: u8[:], other: u8[:]) {
    var xs = first;
    for i in xs.len { xs[i] = 17; xs = other; }
}
fn image(xs: u8[:]) -> u64 {
    var bits: u64 = 0;
    for value, index in xs { bits |= (value as u64) << (index * 8); }
    return bits;
}

fn main() {
    let count = bench_input();
    let seed = bench_input();
    let value = seed as! u8;
    var unsigned: u8[8] = [125; 8];
    bytes(unsigned[1..count + 1], value);
    bytes(unsigned[..0], 255);
    print(image(unsigned));
    var negative: i8[8] = [-7; 8];
    signed(negative[1..count + 1], seed as! i8);
    print(negative);
    var effect: u8[8] = [125; 8];
    effects(effect[1..count + 1]);
    print(image(effect), " ", calls);
    var reference: u8[8] = [125; 8];
    var refvalue = value;
    linked(reference[1..count + 1], refvalue);
    print(image(reference));
    var different: u8[8] = [125; 8];
    varying(different[1..count + 1], value);
    print(image(different));
    var first: u8[8] = [91; 8];
    var second: u8[8] = [92; 8];
    rebound(first[1..count + 1], second[1..count + 1]);
    print(image(first), " ", image(second));
}
