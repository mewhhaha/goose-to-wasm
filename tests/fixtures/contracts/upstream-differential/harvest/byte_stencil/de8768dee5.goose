inline fn nearby(g:u8[:],w:i64,h:i64,x:i64,y:i64)->i64 {
    var n=0;
    for dy in -1..2 { for dx in -1..2 {
        if dx==0 && dy==0 { continue; }
        let nx=(x+dx)%w; let ny=(y+dy)%h;
        n+=g[ny*w+nx];
    }}
    return n;
}
var incoming:u8[:]; var outgoing:u8[:];
var first:u8[4]=[17,34,51,68]; var second:u8[4]=[81,82,83,84];
export fn evolve(w:i64,h:i64) {
    let src=incoming; let dst=outgoing;
    for y in h { for x in w {
        let n=nearby(src,w,h,x,y);
        let alive=src[y*w+x]==1;
        dst[y*w+x]=if n==3 || (alive && n==2) {1} else {0};
    }}
}
fn main() { incoming=first[..]; outgoing=second[..]; }
