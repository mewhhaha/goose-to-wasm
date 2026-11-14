var rows:u8[varint]=[7;128];
export fn length()->i64{rows.len}
export fn first()->u8{rows[0]}
export fn last()->u8{rows[rows.len-1]}
export fn clone()->i64{let out:u8[varint]=copy(rows);return out.len;}
fn main(){}