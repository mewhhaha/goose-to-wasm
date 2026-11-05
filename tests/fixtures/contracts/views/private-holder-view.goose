struct Holder { view: u8[:] }
fn read(holder: Holder&) -> u8[:] { let view = holder.view; return view; }
fn main() {
    var text: u8[>..] = [97, 98]; var best = text[..];
    { var holder = Holder { view: text[..] }; best = read(holder); }
    assert(best == "ab"); print("private holder view passed");
}
