let big:u64=18446744073709551615;let small:u64=3;fn main(){var xs:i64[>..]=[1,2,3];var buffer:i64[..8]=[];let n=xs.len;assert(big>xs.len&&buffer.cap<big&&big>n);xs.push(4);assert(big>n);print(n);}
