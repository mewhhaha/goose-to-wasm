struct Box { values: const i64[2] }
fn mutate(v:i64[2]&) {v[0]=9;}
fn main(){var box=Box{values:[1,2]};mutate(box.values);print(box.values);}
