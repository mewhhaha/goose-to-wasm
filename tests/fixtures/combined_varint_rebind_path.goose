struct H{view:varint[:]}
var a:varint[]=[1,64,-65,8192];var b:varint[]=[-8193,2,300,4];
var h=H{a[..]};var calls=0;
recursive fn get()->H&{calls++;return h;}
fn main(){
 for x,i in get().view {print(i," ",x);if i==0{h.view=b[..];continue;}}
 print("calls ",calls);
}
