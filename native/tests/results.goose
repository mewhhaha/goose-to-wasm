struct Node { value: i64, me: Node&<u32> }
struct Pooled { value: i64, me: Pooled&<u16 in pool> }
struct Linked { value: i64, next: Linked&<u32>? }
var pool: Pooled[>..] = [];
var effects: i64 = 0;
fn tail(value: i64) -> i64[>..] { effects += 1;[value] }
fn pair(value: i64) -> Node, i64[>..], i64 {
    return Node { value: value, me: self }, tail(value + 1), value + 2;
}
fn forward(value: i64) -> Node, i64[>..], i64 { return pair(value); }
fn leave(value: i64) { return forward(value) from distant; }
fn distant(value: i64) -> Node, i64[>..], i64 { leave(value);return pair(0); }
fn pooled(value: i64) -> Pooled, i64[>..] {
    return Pooled { value: value, me: self }, tail(value + 1);
}
fn linked_leave(first: Linked&) { return Linked { value: 2, next: first }, tail(50) from linked_far; }
fn linked_far(first: Linked&) -> Linked, i64[>..] { linked_leave(first);return Linked { value: 0, next: null }, []; }
fn extend(values: i64[>..]&) -> i64 { values[0] += 10;values.push(99);values.len }
fn growth() -> i64[>..], i64, i64[>..] {
    var values: i64[>..] = [3];return values, extend(values), values;
}
fn copied(values: i64[>..]) -> i64[>..], i64, i64[>..] { return values, extend(values), values; }
fn main() {
    let node, array, scalar = forward(7);
    assert(node.me.value == 7 && array[0] == 8 && scalar == 9 && effects == 1);
    let other, rest, end = distant(10);
    assert(other.me.value == 10 && rest[0] == 11 && end == 12 && effects == 2);
    var nodes: Node[>..] = [];
    nodes.push(forward(20));
    assert(nodes[0].me.value == 20 && effects == 3);
    pool.push(pooled(30));
    assert(pool[0].me.value == 30 && effects == 4);
    var links: Linked[>..] = [Linked { value: 1, next: null }];
    links.push(linked_far(links[0]));
    let previous = links[1].next;assert(previous);if previous { assert(previous.value == 1); }
    assert(effects == 5);
    let before, count, after = growth();
    assert(before.len == 1 && before[0] == 13 && count == 2 && after == [13, 99]);
    let initial, size, final = copied([3]);
    assert(initial == [3] && size == 2 && final == [13, 99]);
    print("native result channels ok");
}
