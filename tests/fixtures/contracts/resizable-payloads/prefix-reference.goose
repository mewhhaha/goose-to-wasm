enum Value { Link { p:i64& }, Rows { items:i64[>..] } }
struct Wrap { id:i64, value:Value.. }
fn main(){ var w=Wrap{9,Value.Rows{[1,2]}}; w.id=10; w.value=Value.Link{w.id}; w.id=12; print(w); }
