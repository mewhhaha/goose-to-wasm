struct Cell {tag:u8,value:u16}
struct Box {lead:u8,items:Cell[..3],after:u8}
var calls:i64=0;
fn next()->i64 {calls+=1;return calls;}
struct Defaulted {value:i64=next()}
recursive fn make(n:i64)->u16[..256] {if n>0{return make(n-1);} return [7,8];}
fn copied(value:u16[..256])->u16[..256] {value[0]+=10;return value;}
fn main() {
    let a=make(4); let b=copied(a); let small:u16[..3]=a[..]; let wide:u16[..256]=small;
    print(a," ",b," ",small," ",wide);
    var box=Box{0x11,[Cell{0x22,0x3344}],0x55};
    let word:u16& =box.items[0].value; box.items.push(Cell{0x66,0x7788}); word+=1;
    print(box.lead as i64," ",box.items.len," ",box.items[0].value as i64," ",box.items[1].value as i64," ",box.after as i64);
    var text:u8[..256]="abc"; text.push('!'); print(text," ",text.len," ",text.cap);
    let empty=default<Defaulted[..0]>(); let unused=default<Defaulted[..256]>();
    print(empty.len," ",empty.cap," ",unused.len," ",calls);
}
