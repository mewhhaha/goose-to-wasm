import member_lib;
struct other::Box { v: i64 }
fn other::inspect(x: Box) -> i64 { x.v + 20 }
var inspect: i64 = 42;
fn inspect(x: i64) -> i64 { x * 2 }
fn inspect(x: memberlib::Box) -> i64 { x.v + 1000 }
fn caller::route(x: memberlib::Box) -> i64 { x.inspect() }
fn caller::fallback(x: memberlib::Box) -> i64 { x.v + 300 }
fn caller::route_fallback(x: memberlib::Box) -> i64 { x.fallback() }
fn local_first(x: memberlib::Box) -> i64 {
    fn inspect(v: memberlib::Box) -> i64 { v.v + 100 }
    x.inspect()
}
fn generic<T>(x: T) -> i64 { x.inspect() }
type Alias = memberlib::Box;
var calls: i64 = 0;
fn make() -> memberlib::Box { calls += 1; memberlib::Box { calls } }
fn argument() -> i64 { calls += 10; 2 }
fn main() {
    let p = memberlib::Box { 3 }; let q = other::Box { 4 };
    assert(p.inspect() == 13 && q.inspect() == 24);
    assert(caller::route(p) == 13 && caller::route_fallback(p) == 303);
    assert(local_first(p) == 103);
    assert(generic(p) == 13 && generic(q) == 24 && generic(3) == 6);
    let alias = Alias { 5 }; assert(alias.inspect() == 15);
    let wrap = memberlib::Wrap<i64> { 7 }; assert(wrap.reveal() == 7);
    let one = memberlib::Choice.One { 6 }; assert(one.rank() == 6);
    assert(memberlib::Choice.Empty.rank() == 0);
    assert(memberlib::inspect == 77 && inspect == 42);
    let marker = memberlib::inspect { 9 }; assert(marker.value == 9);
    assert(memberlib::inspect(p) == 13);
    { let inspect = 8; assert(inspect == 8 && p.inspect() == 13); }
    assert(make().plus(argument()) == 3 && calls == 11);
    print("member namespaces passed");
}
