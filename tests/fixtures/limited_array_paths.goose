struct Bag { values: i64[..4] }
struct Link { values: i64[..4]& }
var bag = Bag { [2, 3, 4] };
var calls = 0;
fn get_bag() -> Bag& { calls++; return bag; }
fn row_index() -> i64 { calls++; return 2; }

fn walk(rows: i64[..4][..3]&, replacement: i64[..4]) -> i64 {
    var total = 0;
    for x in rows[2] { total += x; rows.pop(); rows.push(replacement); }
    return total;
}
fn walk_slices(rows: i64[:][..3]&, replacement: i64[:]) -> i64 {
    var total = 0;
    for x in rows[2] { total += x; rows.pop(); rows.push(replacement); }
    return total;
}
fn main() {
    var rows: i64[..4][..3] = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]];
    print(walk(rows, [100]));
    rows[2] = [9, 10, 11, 12];
    var total = 0;
    for x in rows[row_index()] { total += x; rows.pop(); rows.push([100]); }
    print(total, " ", calls);
    total = 0;
    for x in get_bag().values { total += x; bag.values = [100]; }
    print(total, " ", calls);
    let long: i64[4] = [1, 2, 3, 4]; let short: i64[1] = [100];
    var slices: i64[:][..3] = [long[..], long[..], long[..]];
    print(walk_slices(slices, short[..]));
    var values: i64[..4] = [10, 20];
    let old = values[..]; let first: i64& = values[0];
    values.clear(); values.push(30); values.push(40);
    print(first, " ", old[0], " ", old[1], " ", old.len);
    var x = 10; var y = 20;
    var references: i64&[..3] = [&x];
    let selected: i64& = references.push(y); selected += 3;
    print(x, " ", y, " ", references.pop(), " ", references[0]);
    var popped: i64[..4][..3] = [[1, 2, 3]];
    total = 0;
    for x in popped.pop() { total += x; popped.clear(); popped.push([100]); }
    print(total);
    var source: i64[..4] = [1, 2, 3]; var other: i64[..4] = [100];
    var link: i64[..4]& = source;
    total = 0;
    for x in &link { total += x; link .= other; }
    print(total);
    link .= source; total = 0;
    for x in link { total += x; link .= other; }
    print(total);
    var holder = Link { source }; total = 0;
    for x in &holder.values { total += x; holder.values .= other; }
    print(total);
    var links: i64[..4]&[1] = [&source]; total = 0;
    for x in &links[0] { total += x; links[0] .= other; }
    print(total);
    var first_rows: i64[..4][1] = [[1, 2, 3]];
    var other_rows: i64[..4][1] = [[100]];
    var window = first_rows[..]; total = 0;
    for x in window[0] { total += x; window = other_rows[..]; }
    print(total);
}
