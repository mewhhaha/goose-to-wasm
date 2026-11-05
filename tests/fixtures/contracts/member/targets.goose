fn a::deep<T>(x: T, stop: bool) -> i64 {
    if stop { return 7 from outer; }
    x
}
fn a::outer(stop: bool) -> i64 { b::outer(stop) + 100 }
fn b::outer(stop: bool) -> i64 { a::deep(3, stop) + 10 }
fn q::deep(stop: bool) -> i64 { if stop { return 9 from q::outer; } 1 }
fn q::outer(stop: bool) -> i64 { r::outer(stop) + 1000 }
fn r::outer(stop: bool) -> i64 { q::deep(stop) + 2000 }
fn over::deep(stop: bool) -> i64 { if stop { return 11 from outer; } 1 }
fn over::outer(x: bool) -> i64 { over::deep(x) + 30 }
fn over::outer(x: i64) -> i64 { over::outer(x > 0) + 100 }
fn main() {
    assert(a::outer(false) == 113 && a::outer(true) == 7);
    assert(a::outer(false) == 113 && a::outer(true) == 7);
    assert(q::outer(false) == 3001 && q::outer(true) == 9);
    assert(over::outer(0) == 131 && over::outer(1) == 111);
    print("namespace return targets passed");
}
