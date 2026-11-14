recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
struct Packet { head:i64[2], values:i64[>..] }
recursive fn make(n:i64)->Packet { return Packet {[n,n+1],[9]}; }
recursive fn read_prefix(xs:i64[:])->i64 {
    var total=0; for value in xs { total+=value; } return total;
}
fn main() {
    let packet=make(10); let kept=packet.head[..]; let temporary=make(3);
    print(read_prefix(kept)," ",read_prefix(temporary.head[..])," ",packet.values[0]);
    packet.head[0]+=2;
    print(read_prefix(kept)," ",packet.head[0]," ",enable().len);
}
