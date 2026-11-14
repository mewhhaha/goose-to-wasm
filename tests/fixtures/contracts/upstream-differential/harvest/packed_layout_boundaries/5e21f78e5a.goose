
struct Record { point: u64&, value: u64 }
enum E { Old { record: Record }, New { value: u64 } }
var fallback: u64 = 0;
recursive fn replace(named: bool) -> E.., u64 {
    var e: E.. = E.Old { Record { fallback, 0 } };
    let kept: u64& = match e { Old &p => p.record.value, _ => fallback };
    if named { return e, 0; } return E.New { 0x0102030405060708 }, kept;
}
fn main() { let e, n = replace(false); print(n); }