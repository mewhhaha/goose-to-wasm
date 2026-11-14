enum Event { Data { id: i64, values: i64[] }, Grow { values: i64[>..] } }
recursive fn make(n: i64) -> Event.Data { var p = Event.Data { n, [n, n + 1] }; return p; }
fn changed(p: Event.Data) -> Event.Data { p.id += 10; p.values[0] += 20; return p; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = copy(a); let c = changed(copy(a));
    let kept: const i64& = a.id; b.values[0] += 100;
    if kept != n || a.values[0] != n || b.values[0] != n + 100 || c.id != n + 10 || c.values[0] != n + 20 { abort("bad variable variant copy"); }
    for i in 100 { if make(i).values[1] != i + 1 { abort("bad variant temporary"); } }
    if kept != n || a.values[0] != n { abort("overwritten variant"); } return n + 1;
}
fn main() {}