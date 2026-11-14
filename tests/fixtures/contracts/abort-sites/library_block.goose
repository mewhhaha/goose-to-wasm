// The program's own block that a library function runs keeps the program's
// lines: a library call made inside it reports the block's line, not the
// line of the call that passed the block, nor the library's.
import std;

fn main() {
    let xs = [5, 6, 7];
    each_chunk(xs, 2) { c, i =>
        print(c[0]);
        if i == 1 { print(min(c[1..])); }
    };
    print("unreachable");
}
