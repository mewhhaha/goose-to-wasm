// A value parameter takes its argument's type exactly but for the type's own
// constness (upstream TopConstEq): const u8[:] and const T[:] outrank T?.
struct W { n: i64 }
fn emit(value: const u8[:], w: W&) { print("bytes ", value.len); }
fn emit<T>(values: const T[:], w: W&) { print("slice ", values.len); }
fn emit<T>(value: T?, w: W&) { print("optional"); }
fn emit(value: i64, w: W&) { print("int"); }
fn write<T>(w: W&, value: T) { value.emit(w); }
fn main() {
    var w = W { 0 };
    var bytes: u8[:] = default<u8[:]>();
    var words: u32[:] = default<u32[:]>();
    let fixed: const u32[:] = default<const u32[:]>();
    write(w, bytes); write(w, words); write(w, fixed); write(w, 3);
    var x = 5; let r: i64? = x; write(w, r);
}
