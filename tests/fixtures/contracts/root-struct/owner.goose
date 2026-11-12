// A root struct owns several independently resizable fields in any order;
// each grows on its own while the fixed field beside them keeps its value.
root struct State {
    names: u8[>..] = [],
    count: i64 = 0,
    values: i64[>..] = [],
    free: i64[>..<] = []
}

fn record(state: State&, value: i64) {
    state.values.push(value);
    state.names.push('a' + value as u8);
    state.count += 1;
}

fn main() {
    var state = State { .. };
    for i in 0..4 { record(state, i); }
    state.free.push(9);
    state.free.pop();
    print(state.count, " ", state.values, " ", state.names, " ", state.free.len);
}
