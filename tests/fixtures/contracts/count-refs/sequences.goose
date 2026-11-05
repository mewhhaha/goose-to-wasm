fn main() {
    var xs: i64[>..] = [1, 2]; var sum = 0;
    for x, i in xs { sum += x; if i == 0 { xs.push(3); } }
    assert(sum == 6 && xs.len == 3);
    for &x in xs { x *= 2; }
    let reference: i64[>..]& = xs; sum = 0;
    for x in reference { sum += x; }
    assert(sum == 12);
    let slice = xs[..]; sum = 0;
    for x in slice { sum += x; }
    assert(sum == 12 && xs == [2, 4, 6]);
    var range_sum = 0; for i in 0..4 { range_sum += i; }
    var plain_sum = 0; for i in 4 { plain_sum += i; }
    assert(range_sum == 6 && plain_sum == 6);
    print("sequence loops preserved");
}
