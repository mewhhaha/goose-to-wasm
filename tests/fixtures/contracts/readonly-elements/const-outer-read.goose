fn read(p: const (u8[:])&) { for e in p { print(e); } }
fn main() { var a: u8[2] = [97, 98]; var s: u8[:] = a; read(s); }
