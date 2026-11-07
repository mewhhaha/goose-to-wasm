struct Text { body: u8[] }
fn make() -> Text[] { [Text { body: "one" }, Text { body: "two" }] }
fn main() { var total: i64 = 0; for text in make() { let view: const u8[:] = text.body[..]; total += view.len; } print(total); }
