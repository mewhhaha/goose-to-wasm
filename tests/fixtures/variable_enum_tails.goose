extern fn bench_input() -> i64;
enum Event { Empty, Count { id: i64 }, Data { tag: u8, id: i64, values: i64[] }, Limited { id: i64, values: i64[..] } }
enum Defaulted { Data { id: i64 = 7, values: i64[] } }
var defaults: Defaulted..;
fn make(n: i64) -> Event.. { return Event.Data { 1, n, [n + 1, n + 2] }; }
fn payload(n: i64) -> Event.Data { var p = Event.Data { 1, n, [n + 1, n + 2] }; return p; }
fn bump_payload(p: Event.Data&) -> i64 { p.id += 10; p.values[0] += 20; return p.id; }
fn bump(e: Event..&) -> i64 { return match e { Data &p => bump_payload(p), Count &p => { p.id += 10; p.id }, _ => -1 }; }
fn score(e: const Event..&) -> i64 { return match e { Empty => 0, Count p => p.id, Data p => p.id + p.values[0] + p.values.len, Limited p => p.id + p.values.len + p.values.cap }; }
fn changed(e: Event..) -> Event.. { bump(e); return e; }
fn aliases(n: i64) -> Event.., i64, Event.. { var e = make(n); return e, bump(e), e; }
fn payload_aliases(n: i64) -> Event.Data, i64, Event.Data { var p = payload(n); return p, bump_payload(p), p; }
fn promoted(n: i64) -> Event.., i64, Event.. { return payload_aliases(n); }
fn grow(p: Event.Limited&) -> i64 { p.values.push(99); return p.values.len; }
inline fn limited_payloads(n: i64) -> Event.Limited, i64, Event.Limited {
    var p = Event.Limited { n, [..4] }; p.values.push(n); return p, grow(p), p;
}
fn limited_promoted(n: i64) -> Event.., i64, Event.. { return limited_payloads(n); }
inline fn relay(n: i64) -> Event.. { return payload(n); }
recursive fn forward(n: i64) -> Event.. { if n <= 0 { return make(7); } return forward(n - 1); }
fn early(n: i64) -> Event.. {
    var e: Event.. = Event.Data { 1, 2, [if n == 1 { return Event.Count { 77 }; } else if n == 2 { return Event.Data { 5, 88, [99] }; } else if n == 3 { return Event.Empty; } else { 3 }; 2] };
    return e;
}
fn main() {
    let n = bench_input(); let original = make(n); let independent = changed(copy(original));
    print(score(original), " ", score(independent));
    let a, marker, b = aliases(n); print(score(a), " ", marker, " ", score(b));
    let pa, pm, pb = promoted(n); print(score(pa), " ", pm, " ", score(pb));
    match original { Data p => { bump(original); print(p.id, " ", p.values, " ", score(original)); }, _ => {} }
    let converted: Event.. = payload(n + 40); let inlined = relay(n + 50);
    let controlled: Event.. = if n > 0 { make(60) } else { Event.Empty };
    let looped: Event.. = loop { var e = make(70); break copy(e); };
    let exited = early(n); let recursive_value = forward(20);
    print(score(converted), " ", score(inlined), " ", score(controlled), " ", score(looped), " ", score(exited), " ", score(recursive_value));
    let limited: Event.. = Event.Limited { n, [..4] };
    match limited { Limited &p => { p.values.push(n); }, _ => {} }
    let saved = copy(limited);
    match limited { Limited &p => { p.values = p.values[..]; p.values.push(99); print(p.id, " ", p.values, " ", p.values.cap); }, _ => {} }
    match saved { Limited p => print(p.id, " ", p.values, " ", p.values.cap), _ => {} }
    let la, lm, lb = limited_promoted(n); print(score(la), " ", lm, " ", score(lb));
    match defaults { Data p => print(p.id, " ", p.values.len) }
}
