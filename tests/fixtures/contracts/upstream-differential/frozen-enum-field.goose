// A struct field of a variable-mode enum type is frozen like the enum value
// itself (§4.4), so assigning the field is an error.
enum Event { Empty, Data { value: i64 } }
struct Slot { id: i64, event: Event.. }

fn main() {
    var s = Slot { 1, Event.Data { 1 } };
    s.event = Event.Empty;
    print(s.event);
}
