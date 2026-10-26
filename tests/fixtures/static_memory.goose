// Large BSS reservations must stay out of the Wasm data payload. Literal
// bytes, including embedded NUL and UTF-8, still need exact initialization.
var bytes: u8[1048577] = [0; 1048577];
var words: u16[1048577] = [0; 1048577];
let text = "A\0B café";
let empty = "";
let suffix = "tail";

fn main() {
    print(bytes[0], " ", bytes[1048576], " ", words[0], " ", words[1048576]);
    bytes[1048576] = 255;
    words[1048576] = 65535;
    print(bytes[1048576], " ", words[1048576], " ", bytes.len, " ", words.len);
    print(text, empty, suffix);
    print(text.len, " ", text[1], " ", empty.len);
}
