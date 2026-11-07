struct Value { n:i64 }
struct Box { value:const Value }
fn mutate(v:Value&) {v.n=9;}
fn main(){var box=Box{value:Value{1}};mutate(box.value);print(box.value.n);}
