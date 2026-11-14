// A return value that leaves through a nonlocal return ends the return: the
// values after it are never evaluated (nor checked), whether the diverging
// call is the value itself or inside an array literal or fill, and whichever
// value it is. At -O2 each exit function is inlined into its target.
fn literal_exit(value: i64) -> i64 { return [value + 2], value + 3 from literal_target; }
fn literal_target(value: i64) -> i64[>..], i64 { return [literal_exit(value)], 2; }
fn fill_exit(value: i64) -> i64 { return value - 1, [value, value], -value from fill_target; }
fn fill_target(value: i64) -> i64, i64[>..], i64 { return 1, [fill_exit(value); 4], 2; }
fn first_exit(value: i64) -> i64 { return value + 1, [value + 2] from first_target; }
fn first_target(value: i64) -> i64, i64[>..] { return first_exit(value), [3]; }
fn last_exit(value: i64) -> i64 { return value * 2, value * 3 from last_target; }
fn last_target(value: i64) -> i64, i64 { return 1, last_exit(value); }

fn main() {
    let xs, b = literal_target(5); print(xs, " ", b);
    let a, ys, c = fill_target(7); print(a, " ", ys, " ", c);
    let d, zs = first_target(9); print(d, " ", zs);
    let e, g = last_target(11); print(e, " ", g);
}
