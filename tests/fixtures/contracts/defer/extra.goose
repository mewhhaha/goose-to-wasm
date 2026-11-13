// Additional defer cases: narrowing, nested exits, generics, recursion,
// fixed and nonfixed results, guard, internal jumps in a body.
struct Pt { x: i64, y: i64 }

fn narrowed(r: i64&?) {
    guard r else { print("none"); return; }
    let q = r;
    defer print("let narrowed ", q);
    print("body");
}

fn nested_exits() -> i64 {
    var total = 0;
    for i in 3 {
        defer print("outer ", i);
        for j in 3 {
            defer print("inner ", i, " ", j);
            if j == 1 { break; }
            if i == 2 { return total; }
            total += 10;
        }
        {
            defer print("block ", i);
            if i == 1 { continue; }
            total += 1;
        }
    }
    return -1;
}

fn early_block(n: i64) -> i64 {
    let v = block {
        defer print("early block done");
        {
            defer print("nested done");
            if n > 0 { break n * 3; }
        }
        n - 1
    };
    return v;
}

fn generic<T>(v: T) -> T {
    defer print("generic ", v);
    return v;
}

recursive fn countdown(n: i64) -> i64 {
    defer print("countdown ", n);
    if n == 0 { return 0; }
    return countdown(n - 1);
}

fn fixed_result() -> Pt {
    var p = Pt { x: 1, y: 2 };
    defer p.x = 100;
    return p;
}

fn other_result() -> u8[>..] {
    var s: u8[>..] = "ab";
    var t: u8[>..] = "x";
    defer { t.push(33); print("t ", t); }
    s.push(99);
    return s;
}

fn guarded(c: bool) {
    defer print("first");
    guard c else { print("leaving"); return; }
    defer print("second");
    print("guarded body");
}

fn internal_jumps() {
    defer {
        var k = 0;
        while true {
            k++;
            if k == 2 { continue; }
            if k > 3 { break; }
            print("k ", k);
        }
        for x in [5, 6] { if x == 6 { break; } print("x ", x); }
    }
    print("internal");
}

fn arms(n: i64) -> i64 {
    match n {
        0 => { defer print("zero arm"); return 10; },
        _ => { defer print("other arm"); },
    }
    return n;
}

fn each<F>(xs: i64[:]) {
    defer print("each done");
    for x in xs { F(x); }
}

fn twice<F>(xs: i64[:]) {
    defer print("twice done");
    each(xs) { F(it); F(it); }
}

fn through_two() -> i64 {
    defer print("through_two done");
    twice([1, 2, 3]) {
        defer print("fv ", it);
        if it == 2 { return it * 7; }
    }
    return 0;
}

fn main() {
    var value = 5;
    narrowed(value);
    narrowed(null);
    print(nested_exits());
    print(early_block(2), " ", early_block(0));
    print(generic(7), " ", generic(true));
    print(countdown(3));
    print(fixed_result());
    print(other_result());
    guarded(false);
    guarded(true);
    internal_jumps();
    print(arms(0), " ", arms(4));
    print(through_two());
}
