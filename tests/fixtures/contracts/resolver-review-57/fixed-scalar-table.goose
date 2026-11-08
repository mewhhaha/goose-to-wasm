import std;
struct Unused { values: i64[>..] }
const table: i64[4] = [3, 5, 7, 11];
fn main() {
    var values: i64[4] = table;
    var total: i64 = 0;
    for i in 4 { values[i] *= 2; total += values[i]; }
    print(total); print(table[0]); print(values[0]); print(values[3]);
}
