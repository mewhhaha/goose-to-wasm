// A failed check inside a standard library function reports the line of the
// program's own call into the library, not the library's: std's min asserts
// a nonempty slice, reached here through a program function.
import std;

fn smallest(xs: i64[:]) -> i64 {
    return min(xs);
}

fn main() {
    let xs = [3, 1, 2];
    print(smallest(xs));
    print(smallest(xs[1..1]));
    print("unreachable");
}
