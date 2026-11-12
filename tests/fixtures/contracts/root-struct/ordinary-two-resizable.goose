// An ordinary struct still holds at most one resizable field, on its tail.
struct State {
    names: u8[>..] = [],
    values: i64[>..] = []
}

fn main() {
    var state = State { .. };
    print(state.values.len);
}
