// Static zero storage must retain its addresses when omitted from the file.
extern fn bench_input() -> i64;

var arena: u8[1048576] = [0; 1048576];
var first: i64 = 17;
var last: i64 = 29;

recursive fn scratch(n: i64) -> i64 {
    let values: i64[64] = [n; 64];
    if n <= 0 { return values[0] + values[63]; }
    return values[0] + scratch(n - 1) + values[63];
}

fn main() {
    let seed = bench_input();
    print(arena[0], " ", arena[1048575], " ", first, " ", last);
    arena[0] = seed as! u8;
    arena[1048575] = (seed + 1) as! u8;
    print(arena[0], " ", arena[1048575], " ", scratch(4));
    print("A\0B");
    let bytes: u8[5] = [0, 67, 0, 68, 0];
    print(bytes);
}
