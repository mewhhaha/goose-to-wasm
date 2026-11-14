enum Event { Empty, Data { id: i64, values: i64[2] } }
recursive fn make(n: i64) -> Event.. { var e: Event.. = Event.Data { n, [n, n + 1] }; return e; }
fn changed(e: Event..) -> Event.. { match e { Data &p => { p.id += 10; p.values[0] += 20; }, _ => {} } return e; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = copy(a); let c = changed(copy(a));
    match a { Data &p => {
        let kept: const i64& = p.id;
        match b { Data &q => { q.values[0] += 100; }, _ => {} }
        if kept != n || p.values[0] != n { abort("bad enum alias"); }
        for i in 100 { let got = match make(i) { Data q => q.id, _ => -1 }; if got != i { abort("bad enum temporary"); } }
        if kept != n || p.values[0] != n { abort("overwritten enum image"); }
    }, _ => abort("wrong enum tag") }
    let b_value = match b { Data p => p.values[0], _ => -1 };
    let c_value = match c { Data p => p.id + p.values[0], _ => -1 };
    if b_value != n + 100 || c_value != 2 * n + 30 { abort("bad enum copy"); }
    return n + 1;
}
fn main() {}