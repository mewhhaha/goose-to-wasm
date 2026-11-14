export fn touch64000()->i64 { var xs:u8[64000]; xs[0]=3; xs[63999]=7; return xs[0] as i64+xs[63999] as i64; }
export fn touch65536()->i64 { var xs:u8[65536]; xs[0]=3; xs[65535]=7; return xs[0] as i64+xs[65535] as i64; }
export fn touch131072()->i64 { var xs:u8[131072]; xs[0]=3; xs[131071]=7; return xs[0] as i64+xs[131071] as i64; }
fn main() {}
