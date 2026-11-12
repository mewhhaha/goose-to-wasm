// The root file declares path packages; greet requires tools, which the root
// declares as well. Inside greet, `import helper;` resolves from greet's own
// root, not from the program's, which has a helper.goose of its own.
import std;
import greet from "./pkgs/greet";
import tools from "./pkgs/tools";
import greet.extra;
import helper;

fn main() { print(hello(), " ", extra_code(), " ", twice(4), " ", program_helper()); }
