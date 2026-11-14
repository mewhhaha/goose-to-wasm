enum Flat { Data { lead: u8, value: i64 } }
var neighbor: i64[>..] = [987654321];
export fn tick(n: i64) -> i64 {
    var values: Flat.Data[>..] = [Flat.Data { 1, n }];
    let kept: const i64& = values[0].value;
    values.append([Flat.Data { 2, n + 1 }; 999]); values.append([Flat.Data { 3, n + 2 }]);
    if kept != n || values.len != 1001 || values[1000].value != n + 2 { abort("bad packed element stride"); } return n + 1;
}
fn main() {}