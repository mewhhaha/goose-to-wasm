struct Value { n: varint, pad 3, sentinel: u32 }
struct Nested { head: u8, value: Value, tail: i16 }
struct References { n: varint, value: i64&, text: const u8[:], sentinel: u16 }
enum Choice { Number { value: varint, tail: i64 }, Empty }
fn field(value: Value&) -> const varint& { value.n }
fn identity<T>(value: T&) -> T& { value }
fn make(value: i64) -> Value { Value { value, 0x12345678 } }
fn pair(value: i64) -> Value, i64 { return make(value), value + 1; }
fn leave(value: i64) { return make(value) from distant; }
fn distant(value: i64) -> Value { leave(value);return make(0); }
fn copied_refs(value: References&) -> References { copy(value) }
fn choice(value: Choice..&) -> i64 {
    match value { Number n => n.value + n.tail, Empty => 0 }
}
fn main() {
    for n in [63, -64, 64, -65, 8191, -8192, 8192, -9223372036854775808, 9223372036854775807] {
        var value = make(n);
        assert(value.n == n && value.sentinel == 0x12345678);
        assert(field(value) == n && identity(value.n) .== value.n);
        let nested = Nested { 7, make(n), -17 };
        assert(nested.head == 7 && nested.value.n == n && nested.value.sentinel == 0x12345678 && nested.tail == -17);
        let a, b = pair(n);assert(a.n == n && b == n + 1);
        let other = distant(n);assert(other == value);
    }
    let empty = default<Value>();assert(empty.n == 0 && empty.sentinel == 0);
    var c: Choice.. = Choice.Number { -300, 2 };assert(choice(c) == -298);
    var integer = 17;
    let references = References { 300, integer, "text", 1234 };
    let copied = copied_refs(references);
    assert(copied.n == 300 && copied.value .== integer && copied.text == "text" && copied.sentinel == 1234);
    print("native canonical images ok");
}
