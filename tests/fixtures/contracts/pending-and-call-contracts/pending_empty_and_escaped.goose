fn main() {
    var words = [];
    words.push("");
    words.push("a\n\xc3\xa9");
    print(words.len); for word in words { print(word.len); }
}
