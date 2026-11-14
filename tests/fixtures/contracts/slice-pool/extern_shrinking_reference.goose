// Only a grow-only array crosses as its header: a reference to a
// grow-shrink array is no fixed-size value and does not cross.
extern fn note_words(words: i64[>..<]&) = "note_words";

fn main() {
    var words: i64[>..<] = [];
    note_words(words);
}
