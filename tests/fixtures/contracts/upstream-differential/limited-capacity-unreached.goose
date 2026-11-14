// A fixed array longer than a limited array's capacity is checked when it
// converts, not when compiled (§9.3), so a program that never reaches the
// conversion is valid and runs.
fn shrink(b: u8[2], c: bool) -> i64 {
    if c { let a: u8[..1] = b; return a.len; }
    return 0;
}

fn main() { print(shrink([1, 2], false)); }
