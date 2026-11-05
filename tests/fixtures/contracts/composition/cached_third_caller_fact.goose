struct Holder { view: u8[:] }
fn read(holder: Holder&) -> u8[:] { let view = holder.view; return view; }
fn run(holder: Holder&, a: bool, b: bool) {
    let value: i64;
    fn target() {
        fn leave() {
            let view = read(holder);
            assert(view == "ab");
            return from target;
        }
        if a { leave(); }
        if b { leave(); }
        value = 1;
        leave();
    }
    target();
    value = 2;
    print(value);
}
fn main() {
    var text: u8[>..] = [97, 98];
    var holder = Holder { view: text[..] };
    run(holder, false, false);
}
