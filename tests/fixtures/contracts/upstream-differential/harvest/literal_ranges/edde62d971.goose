fn main() {
    var grown:varint[>..]=[1,64];
    for value in grown {
        print(value);
        if value==1 { grown.push(-65); continue; }
        if value==64 { grown.push(8192); continue; }
    }
    print(grown);
    var first:varint[]=[1,64,-65,8192];
    var second:varint[]=[-8193,2,300,4];
    var view:varint[:]=first[..];
    for value in view {
        print(value);
        if value==1 { view=second[..]; continue; }
        if value==300 { view=first[..]; continue; }
    }
}