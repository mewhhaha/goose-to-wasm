var X: i64 = 1;
var R: i64& = &X;
var A: i64 = initial();
var Y: i64 = 10;
var Z: i64 = delayed();
fn initial() -> i64 { X++; X += 2; R .= &X; X }
fn delayed() -> i64 { let value: i64; value = 9; value }
fn mutate() { Y = 14; Y++; R .= &Y; }
fn main() {
    assert(X == 4 && A == 4 && R == 4 && Z == 9);
    X = 20; X++; X += 2; assert(X == 23);
    R .= &Y; R = 12; assert(Y == 12 && R == 12);
    mutate(); assert(Y == 15 && R == 15 && A == 4);
    print("post-init mutations passed");
}
