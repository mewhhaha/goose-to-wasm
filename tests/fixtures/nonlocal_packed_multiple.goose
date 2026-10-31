struct Cell<T> { tag:u8, value:T }
enum Choice { Packed { tag:u8, value:u16 }, Dynamic { values:u8[] } }
recursive fn make(depth:i64) -> Cell<u16>[u8],Choice.Packed[..],i64 {
    if depth > 0 { return make(depth-1); }
    return [Cell<u16>{7,300},Cell<u16>{8,400}],[Choice.Packed{9,500},Choice.Packed{10,600}],17;
}
recursive fn leave(depth:i64) {
    if depth > 0 { leave(depth-1); return; } return make(4) from target;
}
recursive fn target() -> Cell<u16>[u8],Choice.Packed[..],i64 {
    var left:Cell<u16>[u8] = [Cell<u16>{1,2}];
    var right:Choice.Packed[..] = [..5]; right.push(Choice.Packed{3,4});
    leave(4); return left,right,0;
}
fn mutate(values:Cell<u16>[..]&) -> i64 { values[0].value=99; 99 }
recursive fn copy_target() -> Cell<u16>[..],i64 {
    var values:Cell<u16>[..] = [..4]; values.push(Cell<u16>{7,300});
    recursive fn escape() { return copy(values),mutate(values) from copy_target; }
    escape(); return values,0;
}
fn main() {
    var a,b,n=target();
    print(a.len," ",a[0].tag as i64," ",a[0].value as i64," ",a[1].tag as i64," ",a[1].value as i64);
    print(b.cap," ",b.len," ",b[0].tag as i64," ",b[0].value as i64," ",b[1].tag as i64," ",b[1].value as i64);
    print(n); let old=b.pop(); print(old.tag as i64," ",old.value as i64);
    b.push(Choice.Packed{11,700}); print(b[1].tag as i64," ",b[1].value as i64);
    var copied,changed=copy_target(); print(copied.cap," ",copied.len," ",copied[0].tag as i64," ",copied[0].value as i64," ",changed);
    copied.push(Cell<u16>{8,400}); print(copied[1].tag as i64," ",copied[1].value as i64);
}
