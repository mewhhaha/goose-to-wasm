fn main() {
    let encoded: varint[] = [3, 130, -2, 0];
    var total = 0; var counts: i64[>..] = [];
    for &n in encoded {
        var iterations = 0;
        for i in n { iterations += 1; if i == 0 { assert(i - 1 == -1); } }
        counts.push(iterations); total += iterations;
    }
    assert(total == 133 && counts == [3, 130, 0, 0]);
    let indexed: i16[4] = [2, 3, 4, 5];
    var count: i32 = 4; var sum = 0;
    for i in &count { sum += indexed[i]; count = 0; }
    assert(sum == 14 && count == 0);
    print("encoded integer counts passed");
}
