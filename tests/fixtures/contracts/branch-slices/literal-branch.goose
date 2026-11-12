// An array literal in a branch is a temporary the slice would outlive.
fn pick(a: bool, xs: const i64[:]) -> i64 {
    let s: const i64[:] = if a { xs } else { [4, 5] };
    return s.len;
}
fn main() { let v = [1, 2, 3]; print(pick(true, v), " ", pick(false, v)); }
