fn array_first<T>(xs: T[2], value: T) -> T { xs[0] + value }
fn scalar_first<T>(value: T, xs: T[2]) -> T { xs[0] + value }
fn main() { print(array_first([1, 2], 0.5), " ", scalar_first(1, [0.5, 1.5])); var narrow: f32 = 0.25; print(array_first([0.5, 2], narrow)); }
