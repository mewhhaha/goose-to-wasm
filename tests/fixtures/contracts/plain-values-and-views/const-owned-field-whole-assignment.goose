struct Value { n:i64 }
struct Box { value:const Value, values:const i64[2] }
fn main(){var box=Box{value:Value{1},values:[1,2]};box.value=Value{3};box.values=[4,5];print(box.value.n," ",box.values);}
