fn main() {
    let text: u8[2048] = [65; 2048];
    var bytes: u8[3] = [97, 98, 99];
    print(bytes[..], " ", block {
        loop { print(text[..], if bytes[0] == 97 { break; } else { 0 }); }
        break 7;
    }, " ", block {
        for &byte in bytes { byte = 'z'; }
        break 8;
    });
}
