namespace memberlib;
struct Box { v: i64 }
struct inspect { value: i64 }
fn inspect(x: Box) -> i64 { x.v + 10 }
var inspect: i64 = 77;
fn plus(x: Box, y: i64) -> i64 { x.v + y }
struct Wrap<T> { v: T }
fn reveal<T>(x: Wrap<T>) -> T { x.v }
enum Choice { One { v: i64 }, Empty }
fn rank(x: Choice) -> i64 { match x { One a => a.v, Empty => 0 } }
