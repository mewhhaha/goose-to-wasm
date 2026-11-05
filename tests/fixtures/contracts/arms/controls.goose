enum Never {}
enum Choice { Left, Right }

fn empty(value: Never) -> i64 {
    match value {
        const for <N, V> in variants<Never> { V => 1, },
        _ => 2
    }
}

fn number(value: Choice) -> i64 {
    match value { const for <N, V> in variants<Choice> { V => 1, } }
}

fn main() {
    assert(number(Choice.Left) == 1 && number(Choice.Right) == 1);
    print("reflected match arms passed");
}
