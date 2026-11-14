// A variable-mode enum value is frozen at construction, whatever its payloads
// hold (§4.4): even a whole assignment of a variant of the same fixed size is
// an error. The write used to be accepted and silently dropped.
enum Event { Empty, Data { value: i64 } }

fn main() {
    var e: Event.. = Event.Data { 1 };
    e = Event.Data { 2 };
    print(e);
}
