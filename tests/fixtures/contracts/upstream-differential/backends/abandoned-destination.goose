// An exit taken while a destination already holds part of a value abandons
// that part (§7.3 Exits). A `return ... from` built behind a named result
// that a further exit cancels leaves the named result as it was; a cancelled
// whole assignment keeps what it built in place (§4.4); a cancelled append
// adds nothing. Each destination prints right after the exit.
struct R { tag: u8, word: u16, values: u8[u8] }

recursive fn stop() -> i64 { return 9 from literal; }
recursive fn literal() -> i64 { return [11, stop()] from grow; }
fn grow() -> i64[>..] {
    var left: i64[>..] = [1, 2];
    print(literal()); return left;
}

recursive fn halt() -> u16 { return 7 from record_exit; }
recursive fn record_exit() -> i64 { return R{0x11, halt(), [0x22]} from record; }
fn record() -> R {
    let r = R{1, 2, [3, 4]};
    print(record_exit()); return r;
}

recursive fn end() -> i64 { return 5 from tuple_exit; }
recursive fn tuple_exit() -> i64 { return [11, 12], 3, [21, end()] from tuple; }
fn tuple() -> i64[>..], i64, i64[>..] {
    var x: i64[>..] = [1, 2]; var y: i64[>..] = [10, 20];
    print(tuple_exit()); return x, 4, y;
}

var items: i64[>..] = [64, -65, 99];
var codes: varint[>..] = [64, -65];
recursive fn assign<F>() -> i64 { items = [1, F(), 8192]; return 0; }
recursive fn assign_codes<F>() -> i64 { codes = [1, F(), 8192]; return 0; }
recursive fn append<F>() -> i64 { items.append([5, F(), 6]); return 0; }
fn assigned(leave: bool) -> i64 { return assign() { if leave { return 3; } else { -1 } }; }
fn coded(leave: bool) -> i64 { return assign_codes() { if leave { return 3; } else { -1 } }; }
fn appended(leave: bool) -> i64 { return append() { if leave { return 4; } else { -1 } }; }

fn main() {
    let xs = grow(); print(xs);
    let r = record();
    print(r.tag as i64, " ", r.word as i64, " ", r.values.len, " ", r.values[0] as i64, " ", r.values[1] as i64);
    let x, n, y = tuple(); print(x, " ", n, " ", y);
    print(assigned(true)); print(items.len, " ", items);
    print(coded(true)); print(codes.len, " ", codes);
    print(appended(true)); print(items.len, " ", items);
}
