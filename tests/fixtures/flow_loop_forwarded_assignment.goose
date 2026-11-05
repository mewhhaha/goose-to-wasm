fn each<F>(n: i64) { for i in n { F(); } } fn main() { let x: i64; fn init() { x = 5; } each(2) { init(); }; }
