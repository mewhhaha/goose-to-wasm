// Assigning a variable-mode enum through a reference writes the frozen
// pointee (§4.4), an error as a direct assignment is. It used to be accepted
// and crashed natively.
enum Event { Empty, Data { value: i64 } }

fn clear(e: Event..&) { e = Event.Empty; }

fn main() {
    var e: Event.. = Event.Data { 1 };
    clear(e);
    print(e);
}
