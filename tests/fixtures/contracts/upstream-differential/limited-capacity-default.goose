// default<T>() of a fixed array is a value, not a literal (§4.2): converting
// it to a smaller limited capacity aborts at run time (§9.3), while one that
// fits converts.
struct Record { tag: u8[..1] }

fn main() {
    let wide: u8[..4] = default<u8[2]>();
    print(wide.len);
    let r = Record { tag: default<u8[2]>() };
    print(r.tag.len);
}
