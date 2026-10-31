extern fn bench_input() -> i64;
struct Frame { id: i64, values: i64[>..] }
enum Choice { Empty, Data { value: i64 } }
fn leave(choice: Choice.Empty) { return Frame { 4, [5] } from target; }
fn leave(choice: Choice.Data) { return Frame { choice.value, [choice.value + 1] } from target; }
fn target(n: i64) -> Frame {
    let choice: Choice = if n > 0 { Choice.Data { n } } else { Choice.Empty };
    leave(choice);
    return Frame { 0, [] };
}
fn main() { var value = target(bench_input()); print(value.id, " ", value.values); }
