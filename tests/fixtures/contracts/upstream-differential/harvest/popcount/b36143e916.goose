recursive fn tally8(value:u8) {
    var bits=value; var count:u8=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
recursive fn tally16(value:u16) {
    var bits=value; var count:i64=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
recursive fn tally32(value:u32) {
    var bits=value; var count:i32=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
recursive fn tally64(value:u64) {
    var bits=value; var count:i8=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
fn main() {tally8(0x0);tally8(0x1);tally8(0x80);tally8(0xff);tally8(0x55);tally16(0x0);tally16(0x1);tally16(0x8000);tally16(0xffff);tally16(0x55);tally32(0x0);tally32(0x1);tally32(0x80000000);tally32(0xffffffff);tally32(0x55);tally64(0x0);tally64(0x1);tally64(0x8000000000000000);tally64(0xffffffffffffffff);tally64(0x55);}