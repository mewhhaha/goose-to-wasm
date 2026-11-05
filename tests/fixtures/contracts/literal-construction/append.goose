fn main() {
    var values: varint[>..] = [];
    var calls = 0;
    fn next() -> i64 { calls += 1; 300 }
    values.append([1, -1]);
    values.append([next(); 3]);
    assert(calls == 1 && values.len == 5);
    var index = 0;
    for value in values {
        if index == 0 { assert(value == 1); }
        else if index == 1 { assert(value == -1); }
        else { assert(value == 300); }
        index += 1;
    }
    assert(index == 5);
    print("literal append construction passed");
}
