extern fn bench_input() -> i64;

// Distinct specializations and repeated calls must not share a polynomial.
fn u32_zero(s:u32)->u32 { var x=s; for bit in 1 { if x&1!=0 { x=(x>>1)^0; } else { x>>=1; } } return x; }
fn u32_one(s:u32)->u32 { var x=s; for bit in 3 { if x&1!=0 { x=(x>>1)^1; } else { x>>=1; } } return x; }
fn u32_top(s:u32)->u32 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0x80000000; } else { x>>=1; } } return x; }
fn u32_ones(s:u32)->u32 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0xFFFFFFFF; } else { x>>=1; } } return x; }
fn u32_crc(s:u32)->u32 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } return x; }
fn u32_empty(s:u32)->u32 { var x=s; for bit in 0 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } return x; }
fn u32_nine(s:u32)->u32 { var x=s; for bit in 9 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } return x; }
fn u64_zero(s:u64)->u64 { var x=s; for bit in 1 { if x&1!=0 { x=(x>>1)^0; } else { x>>=1; } } return x; }
fn u64_one(s:u64)->u64 { var x=s; for bit in 3 { if x&1!=0 { x=(x>>1)^1; } else { x>>=1; } } return x; }
fn u64_top(s:u64)->u64 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0x8000000000000000; } else { x>>=1; } } return x; }
fn u64_ones(s:u64)->u64 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0xFFFFFFFFFFFFFFFF; } else { x>>=1; } } return x; }
fn u64_crc(s:u64)->u64 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0xC96C5795D7870F42; } else { x>>=1; } } return x; }
fn u64_empty(s:u64)->u64 { var x=s; for bit in 0 { if x&1!=0 { x=(x>>1)^0xC96C5795D7870F42; } else { x>>=1; } } return x; }
fn u64_nine(s:u64)->u64 { var x=s; for bit in 9 { if x&1!=0 { x=(x>>1)^0xC96C5795D7870F42; } else { x>>=1; } } return x; }
fn swapped(s:u32)->u32 { var x=s; for bit in 8 { if x&1==0 { x>>=1; } else { x=(x>>1)^0xEDB88320; } } return x; }
fn plain_shift(s:u64)->u64 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0xC96C5795D7870F42; } else { x=x>>1; } } return x; }
fn arbitrary_five(s:u64)->u64 { var x=s; for bit in 5 { if x&1!=0 { x=(x>>1)^0xA24BAED4963EE407; } else { x>>=1; } } return x; }

fn signed(s:i64)->i64 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^0x123456789; } else { x>>=1; } } return x; }
recursive fn referenced(x:u32&) { for bit in 8 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } }
fn framed(s:u32)->u32 {
    var x=s; let alias:u32& = x;
    for bit in 8 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } }
    return alias;
}
var global_state:u32=0;
fn global_fold() { for bit in 8 { if global_state&1!=0 { global_state=(global_state>>1)^0xEDB88320; } else { global_state>>=1; } } }
fn binder(s:u32)->u32 {
    var x=s;
    for bit in 8 { if x&1!=0 { x=(x>>1)^(0xEDB88320^(bit as! u32)); } else { x>>=1; } }
    return x;
}
recursive fn runtime_polynomial(s:u32,p:u32)->u32 {
    var x=s; for bit in 8 { if x&1!=0 { x=(x>>1)^p; } else { x>>=1; } } return x;
}
fn shift_two(s:u32)->u32 { var x=s; for bit in 8 { if x&1!=0 { x=(x>>2)^0xEDB88320; } else { x>>=2; } } return x; }
fn mask_two(s:u32)->u32 { var x=s; for bit in 8 { if x&2!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } return x; }
var calls=0;
recursive fn touch() { calls++; }
fn effect(s:u32)->u32 {
    var x=s; for bit in 8 { touch(); if x&1!=0 { x=(x>>1)^0xEDB88320; } else { x>>=1; } } return x;
}
fn differing(s:u32)->u32 {
    var x=s; var y=s^0xA5A5A5A5;
    for bit in 8 { if x&1!=0 { x=(x>>1)^0xEDB88320; } else { y>>=1; } }
    return x^y;
}

fn main() {
    let seed=bench_input(); let polynomial=bench_input() as! u32;
    let a=seed as! u32; let b=seed as! u64;
    print(u32_zero(a)," ",u32_one(a)," ",u32_top(a)," ",u32_ones(a)," ",u32_crc(a)," ",u32_empty(a)," ",u32_nine(a)," ",swapped(a));
    print(u64_zero(b)," ",u64_one(b)," ",u64_top(b)," ",u64_ones(b)," ",u64_crc(b)," ",u64_empty(b)," ",u64_nine(b)," ",plain_shift(b)," ",arbitrary_five(b));
    print(u32_crc(u32_crc(a))," ",u64_crc(u64_crc(b))," ",u32_top(a)," ",u64_one(b));
    var ref_state=a; referenced(ref_state); global_state=a; global_fold();
    print(signed(seed)," ",ref_state," ",framed(a)," ",global_state," ",binder(a));
    print(runtime_polynomial(a,polynomial)," ",shift_two(a)," ",mask_two(a)," ",effect(a)," ",calls," ",differing(a));
}
