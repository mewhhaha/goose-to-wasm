struct Pair { x: i64 = 3, y: i64 = 5 }
struct Packed { flag: bool = true, value: i64 = 9 }
struct Owned { values: i64[>..] }
struct Large { values: i64[1024] }
recursive fn explicit(n: i64) -> Pair { return Pair { x: n, y: 7 }; }
recursive fn natural(n: i64) -> Pair { Pair { x: n, y: 8 } }
recursive fn early(n: i64) -> Pair {
    if n > 0 { return Pair { x: n, y: 9 }; }
    Pair { x: -n, y: 10 }
}
recursive fn nested(n: i64) -> Pair {
    if n > 0 { if n > 2 { return Pair { x: n, y: 11 }; } }
    return Pair {};
}
recursive fn defaults() -> Pair { return Pair {}; }
recursive fn recur(n: i64) -> Pair {
    if n <= 0 { return Pair {}; }
    let previous = recur(n - 1);
    return Pair { x: previous.x + 1, y: previous.y + 2 };
}
recursive fn packed(n: i64) -> Packed { return Packed { value: n }; }
recursive fn owned(n: i64) -> Owned { return Owned { values: [n, n + 1] }; }
recursive fn large(n: i64) -> Large { return Large { values: [n; 1024] }; }
recursive fn tuple(n: i64) -> Pair, i64 { return Pair { x: n, y: 6 }, n + 1; }
recursive fn nonlocal(n: i64) -> Pair {
    recursive fn leave(exit: bool) -> i64 {
        if exit { return Pair { x: n, y: 12 } from nonlocal; }
        return 1;
    }
    let normal = leave(n > 0);
    return Pair { x: -n, y: 13 + normal - 1 };
}
recursive fn sum(p: Pair) -> i64 { return p.x + p.y; }
fn main() {
    print(sum(explicit(4)), " ", sum(natural(4)), " ", sum(early(4)), " ", sum(early(-4)), " ",
          sum(nested(4)), " ", sum(nested(1)), " ", sum(defaults()), " ", sum(recur(2)));
    let item = packed(4); let cells = [item]; let bytes = bytes_of(cells);
    assert(bytes.len == 9 && bytes[0] == 1 && bytes[1] == 4);
    for i in 2..9 { assert(bytes[i] == 0); }
    print(item.flag, " ", item.value, " ", bytes.len);
    let resources = owned(4); let fixed = large(4); let a, b = tuple(4);
    print(resources.values[0] + resources.values[1], " ", fixed.values[0] + fixed.values[1023], " ", sum(a) + b, " ",
          sum(nonlocal(4)), " ", sum(nonlocal(-4)));
    var total = 0;
    for i in 5 { explicit(i); total += sum(natural(i)); }
    print(total);
}
