var empty:u8[varint];fn main(){print(empty.len);let a0:u8[varint]=[];print(a0.len);
let a1:u8[varint]=[7;1];print(a1.len," ",a1[0] as i64," ",a1[0] as i64);
let a127:u8[varint]=[7;127];print(a127.len," ",a127[0] as i64," ",a127[126] as i64);
let a128:u8[varint]=[7;128];print(a128.len," ",a128[0] as i64," ",a128[127] as i64);
let a16383:u8[varint]=[7;16383];print(a16383.len," ",a16383[0] as i64," ",a16383[16382] as i64);
let a16384:u8[varint]=[7;16384];print(a16384.len," ",a16384[0] as i64," ",a16384[16383] as i64);}
