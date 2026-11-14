enum Event { Data { id: i64, values: i64[] } }
recursive fn prefix(n: i64) -> Event.Data {
    return Event.Data { if n > 0 { return Event.Data { 7, [8, 9] }; } else { 2 }, [3, 4] };
}
recursive fn tail(n: i64) -> Event.Data {
    return Event.Data { 2, [3, if n > 0 { return Event.Data { 7, [8, 9] }; } else { 4 }] };
}
export fn tick(n: i64) -> i64 {
    let a = prefix(n % 2); let b = tail(n % 2); let expected = if n % 2 > 0 { 7 } else { 2 };
    if a.id != expected || b.id != expected || a.values[0] != expected + 1 || b.values[1] != expected + 2 { abort("bad interrupted variant"); }
    return n + 1;
}
fn main() {}