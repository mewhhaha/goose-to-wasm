fn main(){
 var a:varint[]=[1,64,-65,8192];var b:varint[]=[-8193,2,300,4];
 var view:varint[:]=a[..];
 for x,i in view {print("s ",i," ",x);if i==0 {view=b[..];continue;} if i==2{view=a[..];continue;}}
 var link:varint[]& =a;
 for x,i in &link {print("r ",i," ",x);if i==0{link .= b;continue;} if i==2{link .= a;continue;}}
}
