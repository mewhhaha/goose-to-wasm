var first = 5;
var second = 100;
var route: i64& = first;
var calls = 0;
var index = 0;
var values = [5, 100];

fn overwrite(value: i64&) -> i64 { calls++; value = 100; return 3; }
fn retarget() -> i64 { calls++; route .= second; return 3; }
fn change_index() -> i64 { calls++; index = 1; return 3; }

fn main() {
    var x = 5;
    x += overwrite(x);
    print(x, " ", calls);
    calls = 0;
    route += retarget();
    print(first, " ", second, " ", route, " ", calls);
    calls = 0;
    values[index] += change_index();
    print(values, " ", index, " ", calls);
}
