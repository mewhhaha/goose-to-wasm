recursive fn count_bits(mask:u16)->i64 {
    var bits=mask; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    return count;
}
fn main() {
    var total=0; var rolling:u64=0;
    for value in 65536 {
        let n=count_bits(value as u16); total+=n;
        rolling=rolling*131+(n as u64);
    }
    print(total," ",rolling);
}