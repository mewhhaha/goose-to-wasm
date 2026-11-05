struct Pair { left: u8[:], right: u8[:] }
fn forward<F>(view: u8[:]) { F(view); }
fn visit<F>(holder: Pair&, choose_left: bool) {
    let copy: Pair = holder;
    let view = if choose_left { copy.left } else { copy.right };
    forward(view) { selected => F(selected); };
}
fn main() {
    var left: u8[>..] = [97, 98];
    var right: u8[>..] = [99, 100];
    var best = left[..];
    {
        var holder = Pair { left: left[..], right: right[..] };
        visit(holder, true) { view => best = view; };
    }
    print(best);
}
