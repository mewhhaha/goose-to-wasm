fn main() {
    let text: u8[2048] = [65; 2048];
    for i in 10000 {
        print(text[..], if i >= 0 {
            print(text[..], if i >= 0 { continue; } else { 0 });
            0
        } else { 0 });
    }
    var sum = 0;
    for i in 10000 {
        loop { print(text[..], if i >= 0 { break; } else { 0 }); }
        sum += i;
    }
    print(sum);
}
