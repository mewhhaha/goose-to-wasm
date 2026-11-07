enum Tag { A, B }
fn main() { reusable var words = []; let x = Tag.A; words.push(match x { A => "abc", B => { return; } }); }
