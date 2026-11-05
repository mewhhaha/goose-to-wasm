struct Txt { body: u8[] }
fn choose(values: Txt[:]) -> i64 { -1 }
fn choose(values: Txt[]) -> i64 { values.len }
fn main() {
    assert(choose([Txt { "x" }, Txt { "y" }]) == 2);
    assert(choose([Txt { "x" }; 3]) == 3);
    print("literal owning overload passed");
}
