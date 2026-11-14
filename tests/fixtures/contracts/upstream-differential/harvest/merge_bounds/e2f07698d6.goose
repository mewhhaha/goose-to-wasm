var saved_left:i64[:]; var saved_right:i64[:]; var saved_out:i64[:];
var first:i64[4]=[17,34,51,68]; var second:i64[4]=[81,82,83,84];
var destination:i64[8]=[111,112,113,114,115,116,117,118];
var effects:i64=0;
export fn merge(start_l:i64,limit:i64,start_r:i64,unused_limit:i64,begin_out:i64)->i64 {
    let left=saved_left; let right=saved_right; let output=saved_out;
    var a=start_l; var b=start_r; var out=begin_out;
    while a<limit && b<right.len {
        if right[b]<left[a] { output[out]=right[b]; b++; }
        else { output[out]=left[a]; a++; }
        out++;
    }
    return out;
}
fn main() {
    saved_left=first[..]; saved_right=second[..]; saved_out=destination[..];
    print(merge(0,4,0,4,0));
    destination=[111,112,113,114,115,116,117,118];
}
