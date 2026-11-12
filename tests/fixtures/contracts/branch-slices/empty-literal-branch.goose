// An empty array literal is still a temporary.
fn pick(a: bool, xs: const i64[:]) -> i64 {
    let s: const i64[:] = if a { xs } else { [] };
    return s.len;
}
fn main() { let v = [1, 2, 3]; print(pick(true, v), " ", pick(false, v)); }
