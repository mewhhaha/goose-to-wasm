struct Board { cells:u8[81], rows:u16[9], cols:u16[9], boxes:u16[9] }
fn bit(d:u8)->u16 { (1<<d) as! u16 }
fn box_of(i:i64)->i64 { (i/27)*3+(i%9)/3 }
recursive fn count_bits(mask:u16)->i64 {
    var bits=mask; var count=0; while bits!=0 { bits&=bits-1; count++; } return count;
}
fn place(b:Board&,i:i64,d:u8) {
    b.cells[i]=d; b.rows[i/9]|=bit(d); b.cols[i%9]|=bit(d); b.boxes[box_of(i)]|=bit(d);
}
fn unplace(b:Board&,i:i64,d:u8) {
    b.cells[i]=0; b.rows[i/9]&=~bit(d); b.cols[i%9]&=~bit(d); b.boxes[box_of(i)]&=~bit(d);
}
fn candidates(b:Board&,i:i64)->u16 {
    let used=b.rows[i/9]|b.cols[i%9]|b.boxes[box_of(i)]; ~used&0x3FE
}
recursive fn probe(b:Board&,i:i64,d:u8)->i64 {
    place(b,i,d); let result=count_bits(candidates(b,i)); unplace(b,i,d); return result;
}
fn main() {
    var b=Board {[0;81],[0;9],[0;9],[0;9]}; print(probe(b,0,1)," ",b.cells[0]," ",b.rows[0]);
}
