// Nor through a generic field.
root struct State<T> { items: T[>..], other: T[>..] }
struct Wrapper<T> { value: T }
struct Use { bad: Wrapper<State<i64>> }
fn main() {}
