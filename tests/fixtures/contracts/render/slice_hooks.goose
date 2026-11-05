struct Holder { value: i64[:] }
struct Forward { value: i64[:]& }
struct ConstHolder { value: const i64[:] }
fn format(out: u8[>..]&, value: i64[:]&) {
    format(out, "M", value.len);
    if value.len > 0 { value = value[1..]; }
}
fn format(out: u8[>..]&, value: const i64[:]) { format(out, "C", value.len); }
fn show(value: i64[:]&) { print("ref:", value); }
fn main() {
    var values: i64[>..] = [1, 2, 3];
    var slot = values[..];
    print("var:", slot); assert(slot.len == 2);
    let binding = values[..];
    print("let:", binding); assert(binding.len == 2);
    var holder = Holder { values[..] };
    print("field:", holder); assert(holder.value.len == 2);
    var array: i64[:][>..] = [values[..]];
    print("element:", array); assert(array[0].len == 2);
    show(slot); assert(slot.len == 1);
    let forwarding = Forward { slot };
    print("forward:", forwarding); assert(slot.len == 0);
    let readonly: const i64[:] = values[..];
    print("const:", readonly); assert(readonly.len == 3);
    var const_holder = ConstHolder { readonly };
    print("const-field:", const_holder); assert(const_holder.value.len == 3);
    var nested: const i64[:][>..] = [readonly, readonly];
    print("nested:", nested); assert(nested[0].len == 3 && nested[1].len == 3);
}
