struct Holder { view: const u8[:] }
fn read(holder: Holder&) -> const u8[:] { let view = holder.view; return view; }
fn length(words: (const u8[:])[:]) -> i64 {
    var count = 0; for word in words { count += word.len; } return count;
}
fn main() {
    var holder = Holder { view: "a" };
    assert(read(holder) == "a");
    let bytes: u8[2] = [98, 99];
    holder.view = bytes[..];
    assert(read(holder) == "bc" && read(holder) == "bc");
    var words: (const u8[:])[>..] = ["a"];
    assert(length(words[..]) == 1);
    words[0] = bytes[..];
    assert(length(words[..]) == 2 && length(words[..]) == 2);
    let a: u8[2] = [100, 101]; let b: u8[2] = [102, 103];
    var same = a[..]; same = b[..]; assert(same == "fg");
    let left = 1; let right = 2; var reference .= left; reference .= right;
    assert(reference == 2);
    print("view initializations passed");
}
