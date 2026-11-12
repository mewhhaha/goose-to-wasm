// A nested function inside a namespaced imported file keeps its enclosing
// function's scope while its body's qualified type names are resolved.
import std;
import imported.helper;

fn main() { print(demo::outer(1), " ", demo::Pair { 2, 3 }.a); }
