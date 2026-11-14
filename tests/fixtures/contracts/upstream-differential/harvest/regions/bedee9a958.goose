enum Event { Empty, Data { id: i64, values: i64[] } }
recursive fn make(n: i64) -> Event.. { var e: Event.. = Event.Data { n, [n, n + 1] }; return e; }
fn changed(e: Event..) -> Event.. { match e { Data &p => { p.id += 10; p.values[0] += 20; }, _ => {} } return e; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = copy(a); let c = changed(copy(a));
    match b { Data &p => { p.values[0] += 100; }, _ => {} }
    for i in 100 { let value = match a { Data p => p.id + p.values[0], _ => -1 }; if value != 2 * n { abort("bad owned match copy"); } }
    let bv = match b { Data p => p.values[0], _ => -1 };
    let cv = match c { Data p => p.id + p.values[0], _ => -1 };
    if bv != n + 100 || cv != 2 * n + 30 { abort("bad enum tail copy"); } return n + 1;
}
fn main() {}