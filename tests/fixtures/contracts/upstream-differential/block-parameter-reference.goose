// A non-fixed lvalue passed to an untyped block parameter binds it by
// reference (§4.1, §7.6): no copy() is needed, and a push through the
// parameter grows the caller's own array.
enum Event { Empty, Data { value: i64 } }
struct Track { id: i64, steps: i64[>..] }
var history: i64[>..] = [3];

fn read<F>(a: i64[]) -> bool { F(a) }
fn grow<F>() { var v: i64[>..] = [1]; F(v); print(v); }
fn event<F>(e: Event..) -> bool { let r = F(e); r }
fn field<F>(t: Track&) { F(t.steps); }
fn global<F>() { F(history); }

fn main() {
    let a: i64[] = [1, 2];
    print(read(copy(a)) { x => x.len == 2 });
    grow() { x => x.push(2); }
    let e: Event.. = Event.Data { 4 };
    print(event(copy(e)) { x => match x { Data &d => d.value == 4, Empty => false } });
    var t = Track { 1, [7] };
    field(t) { x => x.push(8); }
    print(t.steps);
    global() { x => x.push(9); }
    print(history);
}
