enum Event { Values { values: i64[] }, Pointer { point: i64&? } }
export fn tick(n: i64) -> i64 {
    var number = n;
    if n >= 0 {
        let prior: Event.. = Event.Pointer { number };
        match prior { Pointer p => { if p.point == null { abort("missing supplied pointer"); } }, _ => {} }
    }
    let empty: Event.. = Event.Pointer {};
    match empty { Pointer p => { if p.point != null { abort("stale omitted pointer"); } }, _ => {} }
    return n + 1;
}
fn main() {}