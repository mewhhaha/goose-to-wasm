// A global owner declared without an initializer takes its field defaults.
// Same-typed components stay distinct: one shrinks while a reference into
// the other is held. Owners in nested scopes, loop exits and early returns
// release their storage, and an owner prints by reference.
root struct Pair { left: i64[>..<], right: i64[>..<], name: u8[] = "pair", turns: i64 = 0 }

var global: Pair;

fn move_one(p: Pair&) -> bool {
    if p.left.len == 0 { return false; }
    p.right.push(p.left.pop());
    p.turns += 1;
    return true;
}
fn drain(p: Pair&) -> i64 { while move_one(p) {} return p.turns; }
fn sum(xs: i64[:]) -> i64 { var s = 0; for x in xs { s += x; } return s; }
fn first_below(limit: i64) -> i64 {
    var p = Pair { [1, 5, 9, 12], [], .. };
    drain(p);
    for x, i in p.right { if x < limit { return i; } }
    return -1;
}

fn main() {
    global.left.append([3, 4, 8]);
    print(drain(global), " ", global.right, " ", global.left.len, " ", global.name);
    let top .= global.right[0];
    global.left.clear();
    global.left.push(top * 2);
    print(top, " ", global.left, " ", sum(global.right[..]), " ", first_below(6));
    var total = 0;
    for round in 0..3 {
        var p = Pair { left: [round, round + 1], right: [10 * round], name: "loop", .. };
        {
            var inner = Pair { [100], [], .. };
            drain(inner);
            total += inner.right[0];
        }
        drain(p);
        total += sum(p.right[..]) + p.turns;
        if round == 1 { break; }
    }
    print(total, " ", global.turns);
    print(global);
}
