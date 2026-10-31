extern fn bench_input() -> i64;
enum Flat { Data { lead: u8, value: i64 } }
struct Box { prefix: u8, payload: Flat.Data, ending: i64 }
fn passthrough(value: Flat.Data) -> Flat.Data { return value; }
fn main() {
    let n = bench_input();
    var rows = [Flat.Data { 1, n }, Flat.Data { 2, n + 1 }, Flat.Data { 3, n + 2 }];
    let kept: const i64& = rows[1].value; let element: Flat.Data& = rows[1];
    for &p in rows { p.value += 10; }
    print(rows.index_of(element), " ", rows[0].value, " ", kept, " ", rows[2].value);
    var box = Box { 7, passthrough(rows[0]), n + 20 }; box.payload.value += 100;
    print(box.prefix, " ", box.payload.lead, " ", box.payload.value, " ", box.ending);
    var grow: Flat.Data[>..] = []; grow.push(rows[1]); grow.append(rows[..]);
    print(grow.len, " ", grow[0].value, " ", grow[3].value);
    let copied = rows; rows[2].value += 100;
    print(copied[2].value, " ", rows[2].value);
}
