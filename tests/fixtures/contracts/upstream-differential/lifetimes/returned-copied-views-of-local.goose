// An owned array of views copied out of a slice holds those views, so a
// copy of views into a local escapes the local when it is returned.
fn copied(xs: const (const i64[:])[:]) -> (const i64[:])[] { return xs; }
fn target() -> (const i64[:])[] {
    var buffer: i64[] = [7, 8];
    var views: (const i64[:])[] = [buffer[..]];
    return copied(views[..]);
}
fn main() { print(target().len); }
