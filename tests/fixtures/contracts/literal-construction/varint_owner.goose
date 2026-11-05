fn total(values: varint[]) -> i64 {
    var sum = 0;
    for value in values { sum += value; }
    sum
}
fn view(values: varint[:]) -> i64 { values.len }
fn main() {
    let values: varint[] = [1, 300, -2];
    assert(total([1, 300, -2]) == 299 && view(values) == 3);
    print("varint owning construction passed");
}
