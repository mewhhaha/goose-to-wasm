struct Cell { x: i64, y: i32 }
struct Box { cells: Cell[..4], marker: i64 }
var shared: i64[..8] = [1, 2];
var alternate: i64[..8] = [50];
var destination: i64[..8]& = shared;

fn make(n: i64) -> i64[..8] { [n, n + 1, n + 2] }
recursive fn descend(n: i64) -> i64[..8] {
    if n == 0 { return make(20); }
    let old = descend(n - 1);
    let sibling = make(n);
    return old;
}
fn change(a: i64[..8]&) -> i64 { a.push(7); return 9; }
fn count(a: i64[..8]&) -> i64 { a.push(8); return 1; }
fn by_value(a: i64[..8]) -> i64[..8] { var b = a; b[0] = 77; return b; }
fn mutate() -> i64 { shared[0] = 99; shared.push(3); return 5; }
fn ordered() -> i64[..8], i64 { return shared, mutate(); }
fn retarget() -> i64 { destination .= alternate; return 6; }

fn main() {
    var a: i64[..8] = [];
    print(a.len, " ", a.cap, " ", a);
    a.push(1); a.push(2); a.append([3, 4]);
    print(a, " ", a[..2], " ", a.len, " ", a.cap);
    a.resize(6, 9); print(a);
    print(a.pop()); a.pop_n(2); print(a);
    a.resize(1); a.clear(); print(a.len);
    a.push(change(a)); print(a);
    a.pop_n(count(a)); print(a);
    a.resize(4, change(a)); print(a);
    let made = make(10); let other = make(30);
    print(made, " ", other, " ", descend(3));
    print(by_value(made), " ", made);
    let before, marker = ordered(); print(before, " ", marker, " ", shared);
    print(shared, " ", mutate(), " ", shared);
    destination.push(retarget()); print(shared, " ", alternate);
    let filled: i32[..5] = [6; 3]; print(filled, " ", filled.len);
    let empty: i64[..0] = []; print(empty.len, " ", empty.cap);
    let zero = default<i64[..4]>(); print(zero, " ", zero.cap);
    var text: u8[..8] = "abc"; text.push('!'); print(text);
    let view: const i64[:] = made; let copied: i64[..8] = view;
    print(copied);
    var box = Box { [Cell { 2, 3 }], 42 };
    box.cells.push(Cell { 4, 5 });
    let last = box.cells.pop(); print(box.cells[0].x, " ", last.y, " ", box.marker);
    var refs: i64[..4] = [];
    let first: i64& = refs.push(12); refs.push(13); first += 2;
    print(refs, " ", first, " ", refs.index_of(first));
    let fixed = [3, 4]; print(fixed.index_of(fixed[1]));
    var overlap: i64[..8] = [2, 3]; overlap.append(overlap[..]); print(overlap);
    let narrow: i64[..3] = made[..]; let wide: i64[..8] = narrow;
    print(narrow, " ", wide);
    var total = 0;
    for v in a { total += v; }
    for i in 1000 { var local: i64[..4] = [i]; local.push(i + 1); total += local.pop(); }
    print(total);
}
