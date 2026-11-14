// What a frozen variable-mode enum still allows (§4.4): a fixed-mode value is
// reassigned, one whose payload holds a resizable tail is assignable whole,
// and a fixed-size field is written through a payload reference.
enum Event { Empty, Data { value: i64 } }
enum Log { Empty, Lines { count: i64, items: i64[>..] } }

fn main() {
    var fixed: Event = Event.Data { 1 };
    fixed = Event.Empty;
    print(fixed);
    var log: Log.. = Log.Lines { 1, [2] };
    log = Log.Empty;
    print(log);
    log = Log.Lines { 2, [3, 4] };
    print(log);
    var e: Event.. = Event.Data { 1 };
    match e { Data &d => { d.value = 5; }, Empty => {} }
    print(e);
}
