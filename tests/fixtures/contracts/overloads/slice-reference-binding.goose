// A slice argument binds a reference parameter only at its own element
// constness, so a mutable slice takes T[:]& and a const one (const T[:])&
// (upstream UnifyArgRaw: the pointee is TypeEq, tier 1 for both).
struct Reader { at: i64 }
struct Entry { offset: u32, len: u32 }
fn get<T>(receiver: Reader&, value: T[:]&) { print("mutable ", value.len); }
fn get<T>(receiver: Reader&, value: (const T[:])&) { print("const ", value.len); }
fn main() {
    var r = Reader { 0 };
    var bytes: u8[:] = default<u8[:]>();
    var words: u32[:] = default<u32[:]>();
    var entries: Entry[:] = default<Entry[:]>();
    var text: const u8[:] = "ab";
    let fixed: const u32[:] = default<const u32[:]>();
    get(r, bytes); get(r, words); get(r, entries); get(r, text); get(r, fixed);
}
