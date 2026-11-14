recursive fn overflow(value:u8) {
    var bits=value; var count:i8=127;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
fn main() { print("before"); overflow(1); }