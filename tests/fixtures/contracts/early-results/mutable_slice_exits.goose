fn touch(r:i64[3]&,rest:i64[>..]&,c:bool){let s=if c{block{break r;}}else{rest[..]};s[0]+=1;}
fn main(){var a:i64[3]=[1,2,3];var b:i64[>..]=[4,5];touch(a,b,true);touch(a,b,false);print(a," ",b);}
