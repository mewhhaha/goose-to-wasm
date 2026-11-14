fn replace(var route: i64[..]&, other: i64[..]&, n: i64) {
    route = [if n >= 0 { route .= other; 42 } else { 43 }, 44];
}
fn interrupted(values: i64[..]&, n: i64) -> i64 { values = [1, if n >= 0 { return 77; } else { 2 }]; return 0; }
export fn tick(n: i64) -> i64 {
    var left: i64[..] = [..4]; left.push(1);
    var right: i64[..] = [..5]; right.push(9);
    replace(left, right, n);
    if left.len != 2 || left[0] != 42 || left.cap != 4 || right[0] != 9 { abort("bad pinned receiver"); }
    if interrupted(left, n) != 77 || left[0] != 42 || left.len != 2 { abort("bad interrupted assignment"); }
    left = left[1..]; left.append([7, 8, 9]);
    if left.len != 4 || left.cap != 4 || left[0] != 44 || left[3] != 9 { abort("bad retained capacity"); }
    return n + 1;
}
fn main() {}