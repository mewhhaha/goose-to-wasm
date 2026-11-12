// The program's total const for expansion size is bounded; the reference
// build allows 1000000 generated nodes, the default 100000.
fn main() {
    var total: i64 = 0;
    const for <A> in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] {
        const for <B> in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20] { total += A * B; }
    }
    print(total);
}
