enum Event { Empty, Data { tag: i64, values: i64[] } }
fn changed(e: Event.Empty, n: i64) -> i64[>..] { return [n]; }
fn changed(e: Event.Data, n: i64) -> i64[>..] { e.values[0] += n; return copy(e.values); }
export fn tick(n: i64) -> i64 {
    let event: Event.. = Event.Data { n, [n, n + 1] };
    let kept = changed(event, 10);
    for i in 100 {
        let other = changed(event, i);
        if other[0] != n + i { abort("wrong copied dispatch payload"); }
    }
    match event { Data &e => { if e.values[0] != n { abort("dispatch mutated source"); } }, Empty => {} };
    if kept[0] != n + 10 || kept[1] != n + 1 { abort("dispatch snapshot escaped"); }
    return n + 1;
}
fn main() {}