struct Holder { view: u8[:] }
fn visit<F>(holder: Holder&) { let copy: Holder = holder; F(copy.view); }
fn main() {
    var text: u8[>..] = [97, 98]; var best = text[..];
    { var holder = Holder { view: text[..] }; visit(holder) { view => best = view; }; }
    print(best);
}
