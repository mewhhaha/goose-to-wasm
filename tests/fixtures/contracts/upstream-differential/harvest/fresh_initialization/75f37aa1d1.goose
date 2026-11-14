
struct Cell { pad 1, tag:u8, pad, value:i32, pad 3, bytes:u8[..4] }
struct Box { cells:Cell[2], tail:i16[3], name:u8[..8] }
struct Defaults { value:i64=7, bytes:u8[3]=[4,5,6] }
enum Choice { Value { number:i64=11, flag:u8=9 }, Empty }
recursive fn run() {
    let box=Box { [Cell { 1,17,[3,4] },Cell { 2,23,[] }],[-2,0,9],"hi" };
    print(box.cells[0].tag," ",box.cells[0].value," ",box.cells[0].bytes.len," ",box.cells[0].bytes.cap);
    print(box.cells[1].bytes.len," ",box.tail[0]," ",box.tail[2]," ",box.name);
    let zero=default<Box>();
    print(zero.cells[0].value," ",zero.cells[0].bytes.len," ",zero.tail[2]," ",zero.name.len);
    let filled=default<Defaults[2]>();
    print(filled[0].value," ",filled[1].bytes[2]);
    let choice=default<Choice>();
    print(match choice { Value v=>v.number+v.flag as i64, Empty=>-1 });
    let empty:u16[..0]=[]; print(empty.len," ",empty.cap);
}
fn main() { run(); }
