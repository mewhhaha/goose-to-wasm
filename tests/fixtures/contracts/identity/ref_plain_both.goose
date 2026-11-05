fn main() {
    let k = 5; let r: const i64& = k;
    let big: u64 = 18446744073709551615;
    assert(big > k);
    assert(k .== r && r .== k);
    assert(big > k);
    print("ref plain identity");
}
