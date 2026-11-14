// A check in a library function that another library function calls, here
// through a function value written in the library, reports the program's
// call that started the chain: heap_pop(xs) calls heap_pop(xs) { a, b => a < b },
// whose xs[0] fails on an empty heap.
import std;

fn main() {
    var heap: i64[>..] = [];
    heap_push(heap, 4);
    heap_push(heap, 2);
    print(heap_pop(heap));
    print(heap_pop(heap));
    print(heap_pop(heap));
    print("unreachable");
}
