struct Name { text:u8[..12] }
recursive fn compare(a:const u8[:],b:const u8[:])->i64 {
    var count=a.len; if b.len<count { count=b.len; }
    for i in count {
        if a[i]<b[i] { return -1; }
        if a[i]>b[i] { return 1; }
    }
    return a.len-b.len;
}
recursive fn names(a:Name,b:Name)->i64 { compare(a.text[..],b.text[..]) }
fn main() { print(names(Name { "ada" },Name { "grace" })); }
