// `values` is the program root's values.goose, `.values` this directory's.
import values;
import .values;
import support.native;

fn describe() -> i64 { return root_value() * 100 + sibling_value() * 10 + native_value(); }
