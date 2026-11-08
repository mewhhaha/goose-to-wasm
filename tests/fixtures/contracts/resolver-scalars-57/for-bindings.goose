fn main() { var sum: i64 = 0; for i in 0..10 { sum += i; } print(sum); var values: i64[3] = [4, 5, 6]; for value, i in values { sum += value + i; } print(sum); }
