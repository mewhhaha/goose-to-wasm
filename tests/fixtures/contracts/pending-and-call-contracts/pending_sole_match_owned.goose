enum Tag { A, B }
fn main() { var words = []; let x = Tag.A; words.push(match x { A => "abc", B => { return; } }); for &word in words { word[0] = 'z'; print(word); }  }
