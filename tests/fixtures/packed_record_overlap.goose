extern fn bench_input() -> i64;
struct Inner { lead: u8, value: u32 }
struct Outer { prefix: u16, inner: Inner, ending: u8 }
enum E { Old { record: Outer }, New { word: u64 }, Empty }
var fallback32: u32 = 0; var fallback64: u64 = 0;
recursive fn forward(n: i64) -> E.., u32 {
    var e: E.. = E.Old { Outer { 0, Inner { 0, 0 }, 0 } };
    let kept: u32& = match e { Old &p => p.record.inner.value, _ => fallback32 };
    if n > 0 { return e, 0; }
    return E.New { if n < 0 { 0xffffffffffffffff } else { 0x0102030405060708 } }, kept;
}
inline fn inlined(n: i64) -> E.., u32 {
    var e: E.. = E.Old { Outer { 0, Inner { 0, 0 }, 0 } };
    let kept: u32& = match e { Old &p => p.record.inner.value, _ => fallback32 };
    if n > 0 { return e, 0; }
    return E.New { if n < 0 { 0xffffffffffffffff } else { 0x0102030405060708 } }, kept;
}
recursive fn reverse(n: i64) -> E.., u64 {
    var e: E.. = E.New { 0 };
    let kept: u64& = match e { New &p => p.word, _ => fallback64 };
    if n > 0 { return e, 0; }
    return E.Old { Outer { 0, Inner { 1, 0 }, 0 } }, kept;
}
fn main() { let n = bench_input(); let a,x=forward(n); let b,y=inlined(n); let c,z=reverse(n); print(x," ",y," ",z); }
