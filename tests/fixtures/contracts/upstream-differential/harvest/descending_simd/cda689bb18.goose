recursive fn alias()->i64 {
    var values:i32[8]=[11,22,33,44,55,66,77,0];let xs=values[..];let key:i32& =xs[7];var j=7;
    while j>0 && xs[j-1]>key { xs[j]=xs[j-1];j--; } print(values);return j;
} fn main() { print(alias()); }