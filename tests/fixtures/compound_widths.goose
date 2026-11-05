struct Small { x: u8, y: u8 }
fn main() {
    var values: u8[2] = [255, 128]; values *= 2;
    let add: u8[2] = [3, 1]; values += add;
    assert(values[0] == 1 && values[1] == 1);
    var pair = Small { 100, 200 }; pair *= 3; pair /= 2;
    assert(pair.x == 22 && pair.y == 44);
    var rows: i32[2][2] = [[6, 8], [10, 12]]; rows /= 2; let more: i32[2][2] = [[1, 1], [2, 2]]; rows += more;
    assert(rows[0][0] == 4 && rows[1][1] == 8);
    print("compound widths passed");
}
