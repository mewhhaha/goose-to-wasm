var selector = 0;
fn static_text() -> const u8[:] { if selector == 0 { return "abcdef"; } return "uvwxyz"; }
let text = static_text();
let part: const u8[:] = text[2..5];
struct Mixed { view: const u8[:], data: i64[>..] }
let mixed = Mixed { part, [10, 20] };
struct Element { view: const u8[:], tag: i64 }
let elements: Element[>..] = [Element { part, 7 }];
var plain: i64[>..] = [4, 5];
thread_fn worker(k: i64) {
    assert(&mixed.view[0] .== &text[2] && &elements[0].view[0] .== &text[2]);
    assert(mixed.data == [10, 20] && elements.len == 1 && elements[0].tag == 7 && plain == [4, 5]);
    let object = &mixed;
    object.data[0] = k;
    object.data.push(k + 1);
    let array = &elements;
    array[0].tag = k;
    array.push(Element { part, k + 1 });
    plain[0] = k;
    plain.push(k + 1);
    assert(object.data == [k, 20, k + 1] && array.len == 2 && &array[0].view[0] .== &part[0]);
    qput(k);
}
fn main() {
    selector = 1;
    for k in 4 {
        thread_wait(thread_spawn(worker, k)); assert(qget<i64>() == k);
        assert(mixed.data == [10, 20] && elements.len == 1 && elements[0].tag == 7 && plain == [4, 5]);
    }
    print("private owners and shared static views ok");
}
