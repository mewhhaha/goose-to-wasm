extern fn bench_input() -> i64;

fn text(n: i64) -> u8[] { str("<", n, ">") }
fn side() -> i64 { print("inner"); 9 }
fn alter(text: u8[>..]&) -> i64 { text.push('!'); 7 }

fn main() {
    let n = bench_input();
    var output: u8[>..] = "start";
    output.format(":", n, ":", true, ":", -0.0, ":", 1.5);
    print(output);
    output.append(text(n));
    print(output, " ", alter(output), " ", output);
    print(str("left", side(), "right"));
    let nested: (u8[])[>..] = ["a\n\"b", "c\\d\t"];
    print(nested);
    print(str(-9223372036854775808, " ", 18446744073709551615));
    var count = 0;
    for i in 10000 {
        let rendered = str("x", i, "y");
        count += rendered.len;
    }
    print(count);
    var growing: u8[>..] = [];
    for i in 10000 { growing.push(('a' as i64 + i % 26) as u8); }
    let part = growing[4000..4100];
    growing.append("tail");
    print(part, " ", growing.len);
}
