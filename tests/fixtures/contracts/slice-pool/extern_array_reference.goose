// A reference to a grow-only array of C-crossing values crosses an extern
// boundary as the array's header (upstream ExternParamOk), whatever its
// element type, as a fixed struct reference crosses as a pointer.
struct Block { a: i64, b: i64[6] }
struct Head { root: i64, height: i64, chain: i64 }
extern fn note_blocks(blocks: Block[>..]&, head: Head&, n: i64) -> i64 = "note_blocks";
extern fn note_words(words: i64[>..]&) = "note_words";

fn main() {
    var blocks: Block[>..] = [];
    var words: i64[>..] = [];
    var head = Head { root: 0, height: 0, chain: 0 };
    print(note_blocks(blocks, head, 3));
    note_words(words);
}
