var outgoing:u16[:]; var incoming:u16[:];
export fn keep(count:i64) { let dst=outgoing; let src=incoming;
    for i in dst.len { dst[i]=1; } for i in count { dst[i]=src[i]; }
} fn main() {}