fn main() { var words = []; words.push(if true { "abc" } else { return; }); for &word in words { word[0] = 'z'; print(word); }  }
