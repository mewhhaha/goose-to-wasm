import std;
var seen: i64 = 0;
recursive fn target(flag: bool) -> i64 {
    var state: i64 = 4;
    var ordinary: i64 = 3;
    recursive fn leave() {
        state += 5;
        seen = state;
        return state * 2 from target;
    }
    if flag { leave(); }
    ordinary *= 7;
    return state + ordinary;
}
fn main() {
    print(target(false)); print(seen); print(target(true)); print(seen);
}
