recursive fn run()->i64 {
    let values:u32[..128]=default<u32[..128]>(); print(values.len," ",values.cap);
    if values.len>0 { return values[0] as i64+values[127] as i64; }
    return 0;
}
fn main() { print(run()); }