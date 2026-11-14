
struct View { bytes:u8[:], value:i64 }
recursive fn seed()->u8[3] { [1,2,3] }
export fn run() {
    var values=seed(); let holder=View { values[..],5 };
    values[0]=9; print(holder.bytes[0]," ",holder.value);
}
fn main() { run(); }
