struct Frame { value: i64 }
struct State { frames: Frame[:], storage: Frame[>..]&, empty: Frame[:] }

fn add(s: State&, value: i64) {
    s.frames = s.empty;
    s.storage.push(Frame { value: value });
    s.frames = s.storage[..];
}
fn main() {
    var frames: Frame[>..] = [Frame { value: 1 }]; var empty: Frame[>..] = [];
    var s = State { frames: frames, storage: frames, empty: empty };
    for i in 0..256 { add(s, i); }
    s.frames[0].value = 7;
    print(s.frames.len, frames[0].value, s.frames[256].value);
}
