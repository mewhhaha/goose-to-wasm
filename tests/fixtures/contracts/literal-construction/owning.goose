struct Txt { body: u8[] }
struct Pair { a: i64, b: i64 }

fn lengths(values: Txt[:]) -> i64 {
    var count = 0;
    for value in values { count += value.body.len; }
    count
}

fn own(values: Txt[]) -> i64 { lengths(values) }

fn sum(values: i64[:]) -> i64 {
    var result = 0;
    for value in values { result += value; }
    result
}

fn pairs(values: Pair[:]) -> i64 {
    var result = 0;
    for value in values { result += value.a + value.b; }
    result
}

fn main() {
    let values: Txt[] = [Txt { "ab" }, Txt { "c" }];
    assert(lengths(values) == 3);
    assert(own([Txt { "ab" }, Txt { "c" }]) == 3);
    assert(own([Txt { "ab" }; 3]) == 6);
    assert(sum([1, 2, 3]) == 6);
    assert(pairs([Pair { 1, 2 }, Pair { 3, 4 }]) == 10);
    print("literal construction passed");
}
