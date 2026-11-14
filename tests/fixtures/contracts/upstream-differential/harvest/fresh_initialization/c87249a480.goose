
struct Record { pad 1, tag:u8, pad, value:i64, pad 3, name:u8[..8] }
var zero:u8[1024];
var record=Record { 3,17,"ok" };
export fn dirty() { for &item in zero { item=99; } record.tag=90; record.value=91; record.name="bad"; }
export fn checksum()->i64 { var total:i64=0; for item in zero { total+=item as i64; } return total; }
export fn literal()->i64 { return record.tag as i64+record.value+record.name.len; }
fn main() {}
