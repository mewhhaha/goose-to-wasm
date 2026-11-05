struct Narrow { n: u8, sentinel: i64 }
var count: i32 = 4;
var calls: i64 = 0;
fn number() -> i32& { calls += 1; count }
fn tally(n) -> i64 { var total = 0; for i in n { total += i; } total }
fn main() {
    var sum = 0;
    for i in number() { count = 0; sum += i + 1; if i == 0 { assert(i - 1 == -1); } }
    assert(sum == 10 && calls == 1 && count == 0);
    var narrow = Narrow { 3, 72623859790382856 };
    sum = 0;
    for i in &narrow.n { sum += i; if i == 0 { assert(i - 1 == 255); } }
    assert(sum == 3 && narrow.sentinel == 72623859790382856);
    let refs: (u8&)[1] = [narrow.n]; sum = 0;
    for i in refs[0] { sum += i + 1; }
    assert(sum == 6);
    var optional: u8? = narrow.n; sum = 0;
    if optional { for i in optional { sum += i; } }
    assert(sum == 3);
    let fixed: i32 = 3; let readonly: const i32& = fixed;
    assert(tally(readonly) == 3 && tally(&narrow.n) == 3);
    var negative = -5; for i in &negative { assert(false); }
    var zero = 0; for i in &zero { assert(false); }
    var b: u8 = 5; sum = 0;
    for i in &b { b += 1; sum += i; }
    assert(sum == 10 && b == 10);
    print("integer count snapshots passed");
}
