struct Holder { view: u8[:] }
fn main() {
    var text: u8[>..] = [97, 98]; var best = text[..];
    { var holder = Holder { view: text[..] }; fn read() { best = holder.view; } read(); }
    assert(best == "ab"); print("direct captured view passed");
}
