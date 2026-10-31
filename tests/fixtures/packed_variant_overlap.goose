extern fn bench_input() -> i64;
enum Shift { Old { lead: u8, value: u64 }, New { value: u64 }, Empty }
enum Widths { Old { lead: u8, small: u16, word: u32, wide: u64 }, New { value: u64 } }
enum Signed { Old { lead: u16, value: i32 }, New { value: i64 } }
var fallback: u64 = 0;
var small_fallback: u16 = 0;
var lead_fallback: u8 = 0;
var word_fallback: u32 = 0;
var signed_fallback: i32 = 0;
recursive fn forward(n: i64) -> Shift.., u64 {
    var e: Shift.. = Shift.Old { 1, 0 };
    let kept: u64& = match e { Old &p => p.value, _ => fallback };
    if n > 0 { return e, 0; }
    return Shift.New { if n < 0 { 0xffffffffffffffff } else { 0x0102030405060708 } }, kept;
}
recursive fn reverse(n: i64) -> Shift.., u64 {
    var e: Shift.. = Shift.New { 0x0102030405060708 };
    let kept: u64& = match e { New &p => p.value, _ => fallback };
    if n > 0 { return e, 0; } return Shift.Old { 1, 0 }, kept;
}
inline fn inlined(n: i64) -> Shift.., u64 {
    var e: Shift.. = Shift.Old { 1, 0 };
    let kept: u64& = match e { Old &p => p.value, _ => fallback };
    if n > 0 { return e, 0; }
    return Shift.New { if n < 0 { 0xffffffffffffffff } else { 0x0102030405060708 } }, kept;
}
recursive fn widths(n: i64) -> Widths.., u8, u16, u32, u64 {
    var e: Widths.. = Widths.Old { 0, 0, 0, 0 };
    let lead: u8& = match e { Old &p => p.lead, _ => lead_fallback };
    let small: u16& = match e { Old &p => p.small, _ => small_fallback };
    let word: u32& = match e { Old &p => p.word, _ => word_fallback };
    let wide: u64& = match e { Old &p => p.wide, _ => fallback };
    if n > 0 { return e, 0, 0, 0, 0; }
    return Widths.New { if n < 0 { 0xffffffffffffffff } else { 0x0102030405060708 } }, lead, small, word, wide;
}
recursive fn signed(n: i64) -> Signed.., i32 {
    var e: Signed.. = Signed.Old { 0, 0 };
    let kept: i32& = match e { Old &p => p.value, _ => signed_fallback };
    if n > 0 { return e, 0; }
    return Signed.New { if n < 0 { -1 } else { 0x0102030405060708 } }, kept;
}
fn main() {
    let n = bench_input();
    let a, first = forward(n); let b, second = reverse(n); let c, third = inlined(n);
    print(first, " ", second, " ", third);
    let e, lead, small, word, wide = widths(n); print(lead, " ", small, " ", word, " ", wide);
    let s, value = signed(n); print(value);
}
