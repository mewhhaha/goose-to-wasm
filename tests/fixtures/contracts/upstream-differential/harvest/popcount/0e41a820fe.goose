var calls=0;
fn lower(value:u16)->u16 { calls++; return value-1; }
recursive fn alias(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    let kept:const u16& = bits; print(kept," ",count);
}
recursive fn captured(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    recursive fn read()->u16 { return bits; }
    print(read()," ",count);
}
recursive fn called(value:u16) {
    calls=0; var bits=value; var count=0;
    while bits!=0 { bits&=lower(bits); count++; }
    print(bits," ",count," ",calls);
}
recursive fn extra(value:u16) {
    var seen=0; var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; seen++; }
    print(bits," ",count," ",seen);
}
recursive fn seeded(value:u16) {
    var bits=value; var count=5;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
recursive fn decrement(value:u16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count--; }
    print(bits," ",count);
}
recursive fn signed(value:i16) {
    var bits=value; var count=0;
    while bits!=0 { bits&=bits-1; count++; }
    print(bits," ",count);
}
fn main() {alias(0x0);captured(0x0);called(0x0);extra(0x0);seeded(0x0);decrement(0x0);signed(0x0);alias(0x8001);captured(0x8001);called(0x8001);extra(0x8001);seeded(0x8001);decrement(0x8001);signed(0x1);alias(0xffff);captured(0xffff);called(0xffff);extra(0xffff);seeded(0xffff);decrement(0xffff);signed(0x7fff);}