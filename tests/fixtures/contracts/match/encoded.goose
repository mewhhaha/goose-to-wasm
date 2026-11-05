struct Encoded { value: varint }

fn main() {
    var source = Encoded { 300 };
    var calls = 0;
    fn next() -> Encoded& { calls += 1; return source; }
    assert(match next().value { 300 => true, _ => false });
    assert(calls == 1);
    let values: varint[] = [-129, -1, 0, 127, 128, 300];
    var sum = 0;
    for value in values {
        sum += match value { -129..0 => 1, 0 => 2, 1..128 => 3, _ => 4 };
    }
    assert(sum == 15);
    var high: u64 = 9223372036854775808;
    let reference: u64& = high;
    assert(match reference { 0..10 => false, 10..18446744073709551615 => true, _ => false });
    print("encoded match passed");
}
