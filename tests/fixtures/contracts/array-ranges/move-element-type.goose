// The source is a slice of the destination's element type.
fn main() { var a = [1, 2]; var b: u8[2] = [1, 2]; a[..].move_from(b[..]); }
