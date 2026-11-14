// A range's index counts iterations from 0 as an i64, whatever the range's
// first value: positive, negative or computed, across continue, break and
// nesting, and next to a count's index, which equals its value.
fn first(n: i64) -> i64 { return n - 7; }

fn main() {
    var values = 0; var indices = 0;
    for v, i in 5..8 { values = values * 10 + v; indices = indices * 10 + i; }
    print(values, " ", indices);
    var negative: u8[>..] = [];
    for v, i in -3..1 { negative.format(v, "@", i, " "); }
    print(negative);
    var skipped: u8[>..] = [];
    for v, i in 10..20 {
        if v % 3 == 0 { continue; }
        if v == 17 { break; }
        skipped.format(v, "@", i, " ");
    }
    print(skipped);
    var computed = 0;
    for v, i in first(10)..first(14) { computed += v * 100 + i; }
    print(computed);
    var grid: u8[>..] = [];
    for y, row in 2..4 { for x, column in -1..1 { grid.format(y, x, ":", row, column, " "); } }
    print(grid);
    var counted: u8[>..] = [];
    for v, i in 3 { counted.format(v, "@", i, " "); }
    print(counted);
}
