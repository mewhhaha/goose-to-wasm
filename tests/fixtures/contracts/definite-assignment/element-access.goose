// A local array or struct need not be assigned as a whole before an element
// or field path writes it, nor an index or slice reads it (upstream
// LValueBase, typecheck_exprs.h): only a whole-value read requires that.
struct Pair { left: i64, items: i64[3] }

fn main() {
    var a: i64[3];
    a[0] = 1; a[1] = 2;
    a[2] = a[0] + a[1];
    a[2] += 10;
    let view = a[0..2];
    print(a[2], " ", view.len, " ", view[1]);
    var grid: u8[4][2];
    grid[1][2] = 7;
    print(grid[1][2]);
    let fixed: i64[2];
    fixed[0] = 5;
    print(fixed[0]);
    var pair: Pair;
    pair.left = 3;
    pair.items[1] = 4;
    pair.items[1] *= 2;
    print(pair.items[1]);
    var later: i64[2];
    if a[2] > 0 { later[0] = 1; } else { later[0] = 2; }
    later[1] = 0;
    print(later[0], " ", later[1]);
}
