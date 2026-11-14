recursive fn narrowed()->i64 {
    var total=0; for value:u8 in 254..256 { total+=value; } return total;
}
recursive fn indexed()->i64 {
    var total=0; for value:u8,index in 254..256 { total+=value+100*index; } return total;
}
fn main() { print(narrowed()," ",indexed()); }
