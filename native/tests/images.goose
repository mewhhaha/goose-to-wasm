struct Packet { head: u8, data: u8[u8], pad 2, tail: i64 }
struct Flags { flags: bool[2] }
enum Tiny { Off, On { value: u16 } }
struct Capacity { values: Tiny[..3] }
struct Dynamic { values: Tiny[..] }
fn main() {
    var records: Packet[>..] = [Packet { head: 7, data: "abc", tail: 42 }];
    var image = to_bytes(records);
    assert(image.len == 16 && image[0] == 15 && image[1] == 7 && image[2] == 3 && image[3] == 'a');
    image[6] = 123;image[7] = 244;
    let decoded, ok = from_bytes<Packet[>..]>(image);
    assert(ok && decoded.len == 1 && decoded[0].head == 7 && decoded[0].data == "abc" && decoded[0].tail == 42);
    let again = to_bytes(decoded);assert(again == image);
    records[0].data[0] = 'x';assert(decoded[0].data[0] == 'a' && image[3] == 'a');
    let badbool: u8[2] = [1, 2];let a, aok = from_bytes<bool[>..]>(badbool);assert(!aok && a.len == 0);
    let nested: u8[3] = [2, 0, 255];let b, bok = from_bytes<Flags[>..]>(nested);assert(!bok && b.len == 0);
    let badprefix: u8[2] = [128, 0];let c, cok = from_bytes<u8[>..]>(badprefix);assert(!cok && c.len == 0);
    let empty: u8[1] = [0];let d, dok = from_bytes<u8[>..]>(empty);assert(dok && d.len == 0);
    let e, eok = from_bytes<u8[>..]>("");assert(!eok && e.len == 0);
    let spare: u8[11] = [10, 1, 1, 42, 0, 255, 255, 255, 255, 255, 255];
    let f, fok = from_bytes<Capacity[>..]>(spare);assert(fok && f.len == 1 && f[0].values.len == 1);
    assert(to_bytes(f) == spare);
    let dynamic: u8[15] = [14, 2, 0, 0, 0, 1, 0, 0, 0, 1, 42, 0, 255, 255, 255];
    let g, gok = from_bytes<Dynamic[>..]>(dynamic);assert(gok && g[0].values.len == 1 && g[0].values.cap == 2);
    assert(to_bytes(g) == dynamic);
    var out: u8[>..] = [99];to_bytes(decoded, out);assert(out.len == image.len + 1 && out[0] == 99 && out[1..] == image);
    for offset in image.len {
        for value in 256 {
            var changed: u8[>..] = copy(image);changed[offset] = value as u8;
            let checked, valid = from_bytes<Packet[>..]>(changed);
            if valid { assert(to_bytes(checked) == changed); } else { assert(checked.len == 0); }
        }
    }
    print("native images ok");
}
