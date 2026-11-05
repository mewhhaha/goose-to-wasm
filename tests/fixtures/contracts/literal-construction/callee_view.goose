struct Txt { body: u8[] }
fn view(values: Txt[:]) -> i64 { values.len }
fn bad() -> Txt[] {
    print(view([Txt { "forbidden temporary" }]));
    [Txt { "a" }]
}
fn main() {
    let values: Txt[] = [Txt { "a" }];
    print(values == bad());
}
