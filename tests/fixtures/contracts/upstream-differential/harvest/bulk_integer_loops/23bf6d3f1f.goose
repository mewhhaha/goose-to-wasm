var calls=0;
recursive fn read(value:i16)->i16 { calls++; return value; }
recursive fn traced(dst:i16[:],src:i16[:],count:i64) { for i in count { dst[i]=read(src[i]); } }
fn main() {
    var rows:i16[5]=[1,2,3,4,5]; traced(rows[1..],rows[..4],4); print(rows," ",calls);
}