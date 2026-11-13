// An operation over a construct of constants adapts only to a type all its
// constants fit: 0 to 300 do not all fit u8 (upstream 71e5ade1).
fn main() {
    var flags: bool[>..] = [true, false];
    let yes = flags[0];
    let z: u8 = (if yes {300} else {0}) + 1;
    print(z);
}
