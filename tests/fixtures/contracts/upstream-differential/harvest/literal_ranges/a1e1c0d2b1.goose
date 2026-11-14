recursive fn visit(values:i64[:])->i64 {
    for &value in values {
        let temporary:i64[>..]=[value,value+1];
        if value==2 { value=20; continue; }
        if value==4 { return temporary[1]; }
        value+=temporary[1];
    }
    return -1;
}
fn main() {
    var values=[1,2,3,4];
    print(visit(values[..])," ",values);
    print(visit(values[..])," ",values);
}