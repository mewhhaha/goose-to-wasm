fn main() {
    var a:u16[..255]=[1;254]; a.push(2);
    print(a.len," ",a.cap," ",a[253] as i64," ",a[254] as i64);
    print(a.pop() as i64); a.append([3]); a.pop_n(253);
    print(a.len," ",a[1] as i64); a.resize(255,7);
    print(a.len," ",a[254] as i64); a.clear(); print(a.len);
    var b:u16[..256]=[4;255]; b.push(5);
    print(b.len," ",b.cap," ",b[254] as i64," ",b[255] as i64);
    let kept:u16& =b[0]; let view:const u16[:]=b[..2];
    b.pop_n(2); b.append([6,7]); kept+=10;
    print(kept as i64," ",view[0] as i64," ",b.len," ",b[254] as i64," ",b[255] as i64);
    b.resize(2); b.resize(256,9);
    print(b.len," ",b[0] as i64," ",b[1] as i64," ",b[255] as i64);
    b.clear(); print(b.len);
}
