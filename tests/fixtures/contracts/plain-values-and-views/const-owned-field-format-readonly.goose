struct Value { n:i64 }
struct Box { value:const Value }
fn format(out:u8[>..]&,v:const Value&) {format(out,v.n);}
fn main(){var box=Box{value:Value{1}};print(box.value);}
