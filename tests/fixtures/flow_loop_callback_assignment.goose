fn each<F>() { for i in 2 { if i == 0 { F(); } else { F(); } } } fn main() { let x: i64; each() { x = 5; }; }
