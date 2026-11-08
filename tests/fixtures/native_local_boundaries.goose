struct Pair { x: i64 = 3, y: i64 = 5 }
struct Owned { values: i64[>..] }
struct Large { values: i64[1024] }
recursive fn branch(n: i64) -> i64 {
    if n > 0 { let positive = Pair { x: n }; return positive.x * 10 + positive.y; }
    else { let negative = Pair { x: -n, y: 7 }; return negative.x + negative.y; }
}
recursive fn repeated(n: i64) -> i64 {
    var total = 0;
    for i in 3 { let iteration = Pair { x: n + i, y: 2 }; total += iteration.x + iteration.y; }
    return total;
}
recursive fn pending(n: i64) -> i64 {
    let later, ignored = Pair { x: n, y: 8 }, Pair {}; return later.x + later.y + ignored.x - 3;
}
recursive fn captured(n: i64) -> i64 {
    let held = Pair { x: n, y: 9 };
    recursive fn read() -> i64 { return held.x + held.y; }
    return read();
}
recursive fn named(n: i64) -> Pair { let result = Pair { x: n, y: 6 }; return result; }
recursive fn named_use(n: i64) -> i64 { let made = named(n); return made.x + made.y; }
recursive fn owned(n: i64) -> i64 {
    let resources = Owned { values: [n, n + 1] }; return resources.values[0] + resources.values[1];
}
recursive fn indirect(n: i64) -> i64 {
    let large = Large { values: [n; 1024] }; return large.values[0] + large.values[1023];
}
recursive fn nonlocal(n: i64) -> i64 {
    let ordinary = Pair { x: n, y: 7 };
    recursive fn leave(exit: bool) -> i64 { if exit { return 41 from nonlocal; } return 1; }
    let saved = ordinary.x;
    return leave(n > 0) + saved;
}
fn main() {
    print(branch(4) + branch(-4), " ", repeated(4), " ", pending(4), " ", captured(4), " ",
          named_use(4), " ", owned(4), " ", indirect(4), " ", nonlocal(4), " ", nonlocal(-4));
}
