// Sharing the receiver's start does not prove containment: the slice runs
// past a fixed row into the next one.
fn main() {
    var rows: u8[2][2] = [[1, 2], [3, 4]];
    print(rows[0].range_index(rows[0][1..]));
    print(rows[0].range_index(rows.bytes_of()));
}
