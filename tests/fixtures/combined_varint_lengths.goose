recursive fn at(xs:const varint[:],index:i64)->i64{for x,i in xs{if i==index{return x;}}abort("missing");}
var empty:varint[varint];fn main(){print(empty.len);
let a0:varint[varint]=[];let a1:varint[varint]=[-65;1];let a127:varint[varint]=[64;127];let a128:varint[varint]=[-65;128];
let a16383:varint[varint]=[8192;16383];let a16384:varint[varint]=[-8193;16384];
print(a0.len," ",a1.len," ",a127.len," ",a128.len," ",a16383.len," ",a16384.len);
print(at(a1,0)," ",at(a127,126)," ",at(a128,127)," ",at(a16383,16382)," ",at(a16384,16383));}