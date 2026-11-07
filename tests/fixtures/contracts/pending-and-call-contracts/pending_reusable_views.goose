const named: const u8[:] = "named";
fn main() {
    reusable var words = [];
    words.push(named);
    let view: const u8[:] = "local";
    let i = words.alloc_index(view);
    let r .= words.alloc_ref(view);
    print(words[0], " ", words[i], " ", r.len, " ", words.len);
}
