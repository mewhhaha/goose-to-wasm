struct Holder { items: i64[2], view: i64[:] }
var data: i64[2] = [1, 2];
var holder = Holder { items: [3, 4], view: data[..] };
fn both() -> i64[:], Holder { return data[..], holder; }
fn main() {
    let view, owned = both();
    holder.items[0] = 8;
    data[0] = 9;
    print(view[0], " ", owned.items[0], " ", owned.view[0]);
}
