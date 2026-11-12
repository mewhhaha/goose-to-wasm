// A call made while one component is under construction may grow another,
// for a local owner and for a global one with field defaults.
root struct S { first: u8[][>..], second: u8[][>..] }
var state: S;
fn other(s: S&) -> u8[] { s.second.push("other"); return "first"; }
fn build(s: S&) { s.first.push(other(s)); }
fn extra() -> u8[] { state.second.push("a"); "b" }
fn main() {
    var a = S { .. };
    build(a);
    state.first.push(extra());
    print(a.first.len, " ", a.second.len, " ", state.first.len, " ", state.second.len);
}
