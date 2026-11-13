// move_from writes the slice captured before its source ran; a view held
// across the copy sees the shorter slice it now stores.
struct Box { view: i64[:] }
var values = [1, 2, 3, 4];
var first = [Box { values[..] }];
var second = [Box { values[..] }];
var replacement = [Box { values[..1] }];
var target: Box[:] = first[..];
fn source() -> Box[:] { target = second[..]; replacement[..] }
fn main() {
    let held .= first[0];
    print(held.view.len);
    target.move_from(source());
    print(second[0].view.len, " ", held.view.len);
    print(held.view[3]);
}
