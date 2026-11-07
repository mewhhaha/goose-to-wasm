fn emit(s: i64[:]) { var value: i64 = 0; for x in s { value = value * 10 + x; } print(s.len, " ", value); }
fn main() { var data = [1, 2, 3, 4, 5];
emit(data[^2..^0]);
emit(data[^5..^0]);
emit(data[^2..^2]);
emit(data[^0..^0]);
emit(data[1..^1]);
emit(data[^4..4]);
emit(data[..^2]);
emit(data[^3..]);
emit(data[..]);
emit(data[2..2]);
emit(data[^5..^5]);
emit(data[..^0]);
}
