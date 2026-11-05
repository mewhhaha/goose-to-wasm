// A local let or annotated global keeps its integer type. An unannotated
// immutable global and a construct of literals adapt to the typed operand.
let Small = 7;
let Typed: i64 = 300;
let Minimum = 9223372036854775808;

fn width(x: i64) -> i64 { 64 }
fn width(x: u8) -> i64 { 8 }

fn main() {
    let local = 300;
    var byte: u8 = 1;
    var choose = false;
    print(local + byte, " ", width(local + byte));
    print(Typed + byte, " ", width(Typed + byte));
    print(Small + byte, " ", width(Small + byte));
    print((if choose { local } else { 301 }) + byte, " ",
        width((if choose { local } else { 301 }) + byte));
    print((if choose { 1 } else { 7 }) + byte, " ",
        width((if choose { 1 } else { 7 }) + byte));
    print(-Minimum);
}
