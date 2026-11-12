import tools from "../tools";
import .internal;
import helper;

fn hello() -> i64 { return internal_code() * 100 + helper_code() * 10 + twice(1); }
