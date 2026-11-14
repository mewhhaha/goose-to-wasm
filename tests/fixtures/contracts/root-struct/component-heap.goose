// A component whose elements own storage (an array of strings) sits beside a
// struct with a growable tail, a record with a variable tail and a shrinking
// array, in a local and a global owner. Direct Wasm keeps such programs'
// arrays on its heap; each component still grows on its own while references
// into the others hold.
struct Tail { flag: bool, values: i64[>..] }
struct Label { id: u16, text: u8[] }
root struct Book { names: u8[][>..] = [], tail: Tail, label: Label, pages: i64[>..<] = [] }

var shelf = Book { tail: Tail { false, [] }, label: Label { 0, "shelf" }, .. };

fn add(b: Book&, name: u8[], value: i64) { b.names.push(copy(name)); b.tail.values.push(value); }
fn letters(b: const Book&) -> i64 { var count = 0; for name in b.names { count += name.len; } return count; }
fn main() {
    var book = Book { [], Tail { true, [7] }, Label { 3, "book" }, [1, 2] };
    let seven .= book.tail.values[0];
    let one .= book.pages[0];
    let title .= shelf.label.text;
    for i in 40 { add(book, "n", i); add(shelf, "sh", 100 + i); shelf.pages.push(i); }
    shelf.pages.pop();
    print(seven, " ", one, " ", book.names.len, " ", letters(book), " ", book.tail.values[40]);
    print(shelf.names.len, " ", letters(shelf), " ", shelf.tail.values[0], " ", shelf.pages.len, " ", title);
    print(book.label, " ", book.pages, " ", shelf.tail.flag);
}
