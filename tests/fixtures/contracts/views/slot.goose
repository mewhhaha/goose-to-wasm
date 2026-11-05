struct Holder { view: const u8[:] }
fn read(slot: (const u8[:])&) -> const u8[:] { let value = slot; return value; }
fn main() {
    var holder = Holder { view: "a" };
    let slot = &holder.view;
    assert(read(slot) == "a");
    let bytes: u8[2] = [98, 99];
    holder.view = bytes[..];
    assert(read(slot) == "bc" && read(slot) == "bc");
    print("slot views passed");
}
