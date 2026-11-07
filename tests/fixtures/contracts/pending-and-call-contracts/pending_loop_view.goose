fn main() {
    reusable var words = [];
    words.push(loop { break "abc"; });
    print(words[0]);
}
