import exception;
struct Pair { x: i64, y: i64 }
struct Wrapper { value: Pair }
fn main() {
    var values = [Pair { 1, 2 }]; var calls = 0; var caught = 0;
    fn index() -> i64 { calls += 1; return 0; }
    fn stop() -> Pair { values[0] = Pair { 50, 60 }; exception::throw("stop"); }
    fn body() { values[index()] += stop(); unknown_after_exit(); }
    fn catcher(error: const u8[:]) { assert(error == "stop" || error == "index"); caught += 1; }
    exception::try<const u8[:]>(body, catcher);
    assert(calls == 1 && caught == 1 && values[0] == Pair { 50, 60 });
    fn stopped_location() -> Wrapper& { calls += 1; exception::throw("index"); }
    fn skipped_rhs() -> Pair { assert(false); return Pair { 7, 8 }; }
    fn lhs_body() { stopped_location().value += skipped_rhs(); unknown_after_index(); }
    exception::try<const u8[:]>(lhs_body, catcher);
    assert(calls == 2 && caught == 2 && values[0] == Pair { 50, 60 });
    print("compound exit passed");
}
