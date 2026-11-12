// A dotted import resolves from the importing file's package root, the root
// file's directory for the program's own files; `import .name;` resolves from
// the importing file's directory.
import std;
import support.io;

fn main() { print(describe()); }
