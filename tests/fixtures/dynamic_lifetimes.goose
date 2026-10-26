extern fn bench_input() -> i64;

struct Item { label: u8[], values: i64[] }
struct Bag { count: i64, items: Item[>..] }

fn item(n: i64) -> Item { Item { str("item-", n), [n, n + 1, n + 2] } }

recursive fn extend(n: i64, values: i64[>..]&) {
    if n > 0 { extend(n - 1, values); }
    values.push(n);
}

fn chain(n: i64) -> i64[>..] {
    var values: i64[>..] = [];
    extend(n, values);
    copy(values)
}

fn pair(n: i64) -> Item, i64, Item { return item(n), n + 1, item(n + 2); }

fn main() {
    let n = bench_input();
    let left, marker, right = pair(n);
    print(left, " ", marker, " ", right);
    let sequence = chain(n);
    print(sequence);
    var bag = Bag { 0, [] };
    for i in 12 { bag.items.push(item(i)); bag.count++; }
    let duplicate = copy(bag);
    print(bag.count, " ", duplicate.count);
    for entry in duplicate.items { print(entry.label, " ", entry.values); }

    var total = 0;
    for i in 10000 {
        let temporary = item(i);
        if i % 3 == 0 { continue; }
        total += temporary.values[1];
        if i == 9998 { break; }
    }
    print(total);
}
