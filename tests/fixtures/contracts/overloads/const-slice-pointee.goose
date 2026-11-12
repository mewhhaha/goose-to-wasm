// A mutable slice cannot bind a reference to a const slice.
fn g(v: (const u32[:])&) { print(v.len); }
fn main() { var m: u32[:] = default<u32[:]>(); g(m); }
