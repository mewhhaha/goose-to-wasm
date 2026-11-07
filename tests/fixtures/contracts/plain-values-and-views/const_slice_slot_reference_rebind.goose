struct Box { text: const u8[:] }
fn main() { var box = Box { text: "abc" }; let r = &box.text; r = "def"; print(box.text); }
