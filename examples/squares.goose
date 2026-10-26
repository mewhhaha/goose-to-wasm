fn sum_squares(count: i64) -> i64 {
    var total: i64 = 0;
    for i in count { total += i * i; }
    return total;
}

fn main() { print("sum=", sum_squares(8)); }
