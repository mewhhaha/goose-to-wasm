struct Txt { body: u8[] }
fn same(values: Txt[:]) -> bool { values == [Txt { "a" }, Txt { "bc" }] }
fn main() {
    var values: Txt[>..] = [];
    values.append([Txt { "a" }, Txt { "bc" }]);
    assert(same(values) && values == [Txt { "a" }, Txt { "bc" }]);
    assert([Txt { "a" }] != values);
    let rows = [[Txt { "a" }], [Txt { "bc" }]];
    assert(rows == [[Txt { "a" }], [Txt { "bc" }]]);
    print("literal comparison views passed");
}
