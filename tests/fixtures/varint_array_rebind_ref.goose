fn main(){
var a:varint[]=[1,64,-65,8192];var b:varint[]=[-8193,2];
var link:varint[]& =a;
for x,i in link {print("plain ",i," ",x);if i==0{link .= b;continue;}}
link .= a;
for x,i in &link {print("address ",i," ",x);if i==0{link .= b;continue;}}
}
