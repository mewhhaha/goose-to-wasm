fn main() {
    var word: i64 = 0x08060402;
    let word_ref: i64&? = &word;
    var bytes: u8[8]& = word_ref as! u8[8]&;
    var v: u8[:] = bytes[0..3];
    var pointer: u8[:]&? = &v;
    var alias: varint[:]& = pointer as! varint[:]&;
    var sum: i64 = 0;
    for x,i in alias {
        sum += x;
        if i == 1 { word = 0x08060482; }
    }
    print(sum);
}
