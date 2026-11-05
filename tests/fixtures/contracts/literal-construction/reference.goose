struct Txt { body: u8[] }
fn length(values: const Txt[]&) -> i64 { values.len }
fn main() { print(length([Txt { "x" }])); }
