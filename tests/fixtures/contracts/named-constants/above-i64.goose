// A named constant above i64.max compared or combined with other named
// constants: the operation is u64. Taking const references to the
// constants keeps them from being folded away before code generation.
let SZ = 15;
let B = SZ * 2;
let HUGE = 18446744073709551615;
let HALF = 9223372036854775808;
fn peek(x: const i64&) -> i64 { x }
fn peek_u(x: const u64&) -> u64 { x }
fn main() {
    print(HUGE > B, " ", HUGE > SZ, " ", HUGE >= B, " ", HUGE == SZ, " ", B < HUGE);
    print(HUGE - SZ, " ", HALF + B, " ", HALF > HUGE);
    let all: u64 = HUGE;
    print(all, " ", peek(SZ), " ", peek(B), " ", peek_u(HUGE));
}
