fn main() {
    reusable var words = [];
    words.push(if true { "a" } else { "b" });
    print(words[0]);
}
