var saved_left:u64[:]; var saved_right:u64[:]; var saved_out:u64[:];
var first:u64[4]=[17,34,51,68]; var second:u64[4]=[81,82,83,84];
var destination:u64[8]=[111,112,113,114,115,116,117,118];
var effects:i64=0;
export fn merge(begin_left:i64,end_left:i64,begin_right:i64,end_right:i64,begin_out:i64)->i64 {
    let left=saved_left; let right=saved_right; let output=saved_out;
    var a=begin_left; var b=begin_right; var out=begin_out;
    while a<=end_left && b<=end_right {
        if left[a]<=right[b] { output[out]=left[a]; a++; }
        else { output[out]=right[b]; b++; }
        out++;
    }
    return out;
}
fn main() {
    saved_left=first[..]; saved_right=second[..]; saved_out=destination[..];
    print(merge(0,3,0,3,0));
    destination=[111,112,113,114,115,116,117,118];
}
