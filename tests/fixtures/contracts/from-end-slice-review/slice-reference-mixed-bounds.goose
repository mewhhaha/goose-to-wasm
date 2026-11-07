fn sum(values: i64[:]) -> i64 { var total: i64 = 0; for value in values { total += value; } return total; }
fn inspect(values: i64[:]&, tail: i64) {
    let ends = values[^4..^1];
    ends[0] = 70;
    let mixed = values[2..^tail];
    let reverse = values[^tail..5];
    print(ends.len, " ", sum(ends), " ", mixed.len, " ", sum(mixed), " ", reverse.len, " ", sum(reverse));
}
fn main() {
    var data: i64[6] = [10, 20, 30, 40, 50, 60];
    var view: i64[:] = data[1..];
    inspect(view, 1);
    print(data[2], " ", view[1]);
}
