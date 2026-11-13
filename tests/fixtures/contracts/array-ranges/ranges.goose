// range_index, check_length and move_from (upstream d6a3ceaa, d24161f4):
// checked starts of contained slices, empty slices from anywhere, counts
// returned unchanged after one evaluation, and overlap-safe copies.
struct Box { view: i64[:] }
fn locate(a: i64[>..]&, s: i64[:]) -> i64 { a.range_index(s) }
fn move<T>(dst: T[:], src: T[:]) { dst.move_from(src); }
fn main() {
    var a: i64[>..] = [10, 20, 30, 40];
    var other: i64[>..] = [50];
    print(a.range_index(a[1..3]), " ", locate(a, a[2..]), " ", a.range_index(a[..]), " ",
          a.range_index(other[..0]), " ", a.range_index(default<i64[:]>()));
    var fixed = [1, 2, 3];
    var limited: i64[..8] = [4, 5, 6];
    var rows: u8[3][2] = [[1, 2, 3], [4, 5, 6]];
    print(fixed.range_index(fixed[1..]), " ", limited.range_index(limited[2..]), " ",
          fixed.range_index(fixed[3..]), " ", rows[1].range_index(rows[1][2..]));
    var count = 0;
    fn length_arg() -> i64 { count++; return 17; }
    let wide: u32 = 5;
    print(a.check_length(length_arg()), " ", count, " ", a.len, " ", a.check_length(0), " ",
          a.check_length(wide), " ", a.check_length(3, "unused"));
    var m = [1, 2, 3, 4, 5];
    m[1..].move_from(m[..4]);
    print(m[0], m[1], m[2], m[3], m[4]);
    move(m[..4], m[1..]);
    print(m[0], m[1], m[2], m[3], m[4]);
    m[..].move_from(m[..]);
    m[..0].move_from(default<i64[:]>());
    var bytes: u8[3] = [0; 3];
    bytes[..].move_from("abc");
    print(bytes[0], " ", bytes[2]);
    var boxes = [Box { m[..4] }, Box { m[..1] }];
    boxes[..1].move_from(boxes[1..]);
    print(boxes[0].view.len, " ", boxes[0].view[0]);
    var refs: i64&[2] = [m[0], m[1]];
    refs[1..].move_from(refs[..1]);
    print(refs[1] .== m[0]);
}
