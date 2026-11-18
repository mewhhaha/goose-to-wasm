struct Row { value: i64, items: i64[3] }

fn add(cell: i64&, n: i64) { cell += n; }
fn update(row: Row&, index: i64) -> i64 {
    add(row.items[index], row.value);
    row.value = row.items[index];
    return row.value;
}
fn choose(var row: Row&, other: Row&, again: bool) -> i64 {
    let before = row.value;
    if again { row .= other; }
    row.value += 1;
    return before * 10 + row.value;
}
fn captured(var row: Row&, other: Row&) -> i64 {
    fn read() -> i64 { row.value }
    let before = read();
    row .= other;
    return before * 10 + read();
}
fn maybe(row: Row&?) -> i64 {
    if row { return row.value; }
    return -1;
}
fn main() {
    var a = Row { value: 2, items: [3, 5, 8] };
    var b = Row { value: 4, items: [1, 2, 3] };
    assert(update(a, 1) == 7);
    assert(a.items[1] == 7);
    assert(choose(a, b, true) == 75);
    assert(choose(a, b, false) == 78);
    assert(captured(a, b) == 85);
    assert(maybe(null) == -1);
    assert(maybe(a) == 8);
    print(a.value, " ", b.value, " ", a.items);
}
