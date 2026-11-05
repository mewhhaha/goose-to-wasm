var selector = 0;
fn static_text() -> const u8[:] {
    if selector == 0 { return "abcdef"; }
    return "uvwxyz";
}
let text = static_text();
let whole: const u8[:] = text;
let part: const u8[:] = text[2..5];
let empty: const u8[:] = text[3..3];
let point: const u8& = text[2];
let absent: const u8? = null;
struct Views { all: const u8[:], part: const u8[:], empty: const u8[:], point: const u8& }
struct Nested { marker: i64, views: Views }
let nested = Nested { 17, Views { text, part, empty, point } };
enum Choice { Empty, Pair { all: const u8[:], part: const u8[:] } }
let fixed: Choice = Choice.Pair { text, part };
let image: Choice.. = Choice.Pair { text, part };
struct Encoded { marker: varint, part: const u8[:], point: const u8& }
let encoded = Encoded { 300, part, point };
fn identities() {
    assert(text == "abcdef" && whole == text && part == "cde" && empty.len == 0);
    assert(&whole[2] .== &part[0] && point .== text[2] && point .== part[0]);
    assert(absent == null);
    assert(nested.marker == 17 && &nested.views.part[0] .== point && &nested.views.all[2] .== point && nested.views.empty.len == 0);
    match fixed { Empty => assert(false), Pair value => assert(&value.all[2] .== &value.part[0] && &value.part[0] .== point) }
    match image { Empty => assert(false), Pair &value => assert(&value.all[2] .== &value.part[0] && &value.part[0] .== point) }
    assert(encoded.marker == 300 && &encoded.part[0] .== encoded.point && encoded.point .== point);
}
thread_fn worker(k: i64) { identities(); qput(k); }
fn main() {
    selector = 1;
    identities();
    print("main static identities ok");
    for k in 4 { thread_wait(thread_spawn(worker, k)); assert(qget<i64>() == k); }
    identities();
    print("worker static identities ok");
}
