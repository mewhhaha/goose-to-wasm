struct Wide { prefix: i64[8], tail: i64 }
fn main() {
    var small: u8[>..] = [];
    let cast: const Wide& = (&small) as! const Wide&;
    let outside: const i64& = &cast.tail;
    print(1);
}
