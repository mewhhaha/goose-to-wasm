// LoadType keeps the declared mutable Slice shape; the outer reference
// makes this read readonly, which the selected hook's instantiation obeys.
struct Outer { value: const (i64[:])& }
fn format(out: u8[>..]&, value: const i64[:]) { format(out, "R", value.len); }
fn main() {
    var values: i64[>..] = [1, 2, 3];
    var slot = values[..];
    let readonly: const (i64[:])& = slot;
    print("outer:", readonly);
    print("mutable:", slot);
    let nested = Outer { readonly };
    print("nested:", nested);
}
