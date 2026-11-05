struct Holder { view: u8[:] }
fn visit<F>(holder: Holder&) { let view = holder.view; F(view); }
fn main() {
    var text: u8[>..] = [97, 98];
    var best = text[..];
    {
        var holder = Holder { view: text[..] };
        fn run(early: bool) {
            visit(holder) { view =>
                if early { best = view; return from run; }
            };
        }
        run(true);
    }
    print(best);
}
