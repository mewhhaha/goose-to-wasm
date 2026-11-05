// Declared const Slice payloads match the const Slice hook, including
// values reached through a reference and a nested reference field.
struct Inner { value: const (const i64[:])& }
fn format(out: u8[>..]&, value: const i64[:]) { format(out, "R", value.len); }
fn main() {
    var values: i64[>..] = [1, 2, 3];
    var slot = values[..];
    let data: const i64[:] = slot;
    let reference: const (const i64[:])& = data;
    print("data:", reference);
    print("mutable:", slot);
    let nested = Inner { reference };
    print("nested:", nested);
}
