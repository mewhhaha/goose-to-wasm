var fills:i64=0;
fn fill()->u8 {fills+=1;return 7;}
fn main() {
    var a:u8[..65535]=[1;65534];a.push(2);
    var b:u8[..65536]=a;b.push(3);
    print(a.len," ",b.len," ",a[65534] as i64," ",b[65535] as i64);
    print(b.pop() as i64);b.append([4]);b.pop_n(65534);
    print(b.len," ",b[0] as i64," ",b[1] as i64);
    b.resize(65536,fill());print(b.len," ",b[65535] as i64," ",fills);
    let c:u8[..65535]=b[..65535];print(c.len," ",c[65534] as i64);
    b.clear();b.append([9,8]);print(b.len," ",b[0] as i64," ",b[1] as i64);
}
