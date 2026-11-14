struct Name { text:u8[..12] }
var saved:const u8[:];
recursive fn escape(p:Name) { saved=p.text[..]; }
fn main() { escape(Name { "ada" }); }
