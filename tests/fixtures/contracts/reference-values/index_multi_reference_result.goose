fn one(v: u8[:]&) -> u8[:]&, i64 { return v, 7; }
fn main() { var h: u8[>..] = []; h.append("abc"); var views: (u8[:])[>..] = []; views.push(h[0..1]); views.push(h[1..2]); let c = views.len > 1; print(views.index_of(one(views[1]))); }
