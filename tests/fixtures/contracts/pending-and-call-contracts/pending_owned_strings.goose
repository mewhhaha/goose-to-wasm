fn main() {
    var words = [];
    words.push("abc");
    words.push("d");
    for &word, i in words { if i == 0 { word[0] = 'z'; } print(word); }
    print(words.len);
}
