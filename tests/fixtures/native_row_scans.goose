struct Row { id: i64 = next_id(0), me: Row&<u32> = self, text: u8[varint] = "default" }
var calls = 0;
recursive fn next_id(i: i64) -> i64 { calls++; return 9 + i; }
fn main() {
    var rows: Row[>..] = [Row{100, self, "original"}];
    for i in 128 { rows.push(Row{id: i}); }
    var sum = 0;
    for r, i in rows {
        if i == 0 { continue; }
        if i == 4 { break; }
        sum = sum * 10 + r.me.id;
    }
    print(sum, " ", rows.len);
    sum = 0;
    for r in rows { sum += r.me.id; }
    print(sum);
    rows = [Row{1, self, "a longer replacement"}];
    for i in 2 { rows.push(Row{next_id(i), self, "xy"}); }
    for r, i in rows {
        r.id += i;
        if i == 0 { rows.push(Row{20, self, "appended mid-loop"}); continue; }
        if i == 2 { break; }
    }
    sum = 0;
    for r in rows { sum += r.me.id; }
    print(sum, " ", rows.len, " ", calls);
    rows = [];
    sum = 0;
    for r in rows { sum += r.me.id; }
    print(sum);
    for i in 2 { rows.push(Row{}); }
    for r in rows { sum += r.me.id; }
    print(sum, " ", calls);
}
