struct Empty {}
struct Item { byte: u8, empty: Empty }
struct Guard { item: Item, sentinel: u8 }

fn replace(dst: Item&, src: const Item&) { dst = src; }

fn main() {
    var a = Guard { Item { 1, Empty {} }, 17 };
    var b = Guard { Item { 2, Empty {} }, 34 };
    replace(a.item, b.item);
    print(a.item.byte as i64, " ", a.sentinel as i64, " ", b.sentinel as i64);
}
