extern fn bench_input() -> i64;
struct Cell<T> { tag: u8, value: T }
struct Wrap { start: u16, item: Cell<i64>, ending: u8 }
struct Frame { head: Cell<u16>, values: i64[>..] }
fn observe(value: Wrap, next: i64) -> i64 { value.item.value + next }
fn mutate(value: Wrap&) -> i64 { value.item.value += 100; value.item.value }
fn main() {
    let n = bench_input();
    var rows = [Wrap { 1, Cell { 2, n }, 3 }, Wrap { 4, Cell { 5, n + 1 }, 6 }, Wrap { 7, Cell { 8, n + 2 }, 9 }];
    let kept: const i64& = rows[1].item.value; let element: Wrap& = rows[1];
    for &p in rows { p.item.value += 10; }
    print(rows.index_of(element)," ",rows[0].item.value," ",kept," ",rows[2].item.value);
    print(observe(rows[0], mutate(rows[0])));
    var grow: Wrap[>..] = []; grow.push(rows[1]); grow.append(rows[..]);
    let popped = grow.pop(); print(grow.len," ",popped.item.value);
    var frame = Frame { Cell<u16> { 5, 6 }, [n] }; let head: const u16& = frame.head.value;
    frame.head.value += 10; frame.values.push(n + 1); print(head," ",frame.values);
}
