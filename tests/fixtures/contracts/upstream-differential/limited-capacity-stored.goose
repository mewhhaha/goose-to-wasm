// Only an array or string literal must fit a limited array's static capacity
// when compiled (§4.2). A stored array converts whatever its static length or
// capacity, and the conversion checks its length at run time (§9.3): a
// limited array that fits converts, and a fixed array longer than the
// capacity aborts where it converts.
fn shrink(b: u8[..4]) -> i64 { let a: u8[..2] = b; return a.len; }

fn main() {
    let fits: u8[..4] = [1, 2];
    print(shrink(fits));
    let b: u8[3] = [1, 2, 3];
    print(b.len);
    let a: u8[..2] = b;
    print(a.len);
}
