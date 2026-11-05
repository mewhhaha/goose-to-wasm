struct Holder { view: u8[:] }
fn read<F>(holder: Holder&) -> u8[:] {
    let view = holder.view;
    F();
    return view;
}
fn choose(holder: Holder&, early: bool) -> u8[:] {
    return read(holder) { if early { return holder.view from choose; } };
}
fn main() {
    var text: u8[>..] = [97, 98];
    var other: u8[3] = [99, 100, 101];
    var holder = Holder { view: text[..] };
    print(choose(holder, false), " ", choose(holder, true));
    holder.view = other[..];
    print(choose(holder, false), " ", choose(holder, true));
}
