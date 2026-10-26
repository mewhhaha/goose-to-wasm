var global_value: i64 = 5;

fn get() -> i64& { global_value }
fn inc(value: i64&) { value += 4; }
fn element(values: i64[3]&, index: i64) -> i64& { values[index] }

fn main() {
    var value = 2;
    inc(value);
    var values: i64[3] = [1, 2, 3];
    inc(element(values, 1));
    inc(get());
    print(value, " ", values, " ", global_value);
}
