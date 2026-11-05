struct Box { n: i64 }
fn inc(n: i64&) { n += 1; }
fn main() { var b = Box { n: 4 }; inc(b.n); let r = &b.n; r += 1; print(b.n); }
