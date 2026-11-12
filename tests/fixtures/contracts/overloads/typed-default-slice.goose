// default<T[:]>() is a typed value, not an untyped [] literal: the exact
// overload outranks the generic one.
struct R { pos: i64 }
fn readValue(self_: R&, sample: const u8[:]) -> const u8[:], i64 { return "text", 1; }
fn readValue<T>(self_: R&, sample: const T[:]) -> const T[:], i64 { return default<const T[:]>(), 2; }
fn readValue(self_: R&, sample: u64) -> u64, i64 { return 7, 3; }
fn read<T>(self_: R&) -> T, i64 { let decoded, error = self_.readValue(default<T>()); return decoded, error; }
fn main() {
    var r = R { 0 };
    let a, ea = read<const u8[:]>(r); let b, eb = read<const u32[:]>(r); let c, ec = read<u64>(r);
    print(a, " ", ea, " ", b.len, " ", eb, " ", c, " ", ec);
}
