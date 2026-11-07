struct P{x:i64,y:i64}
fn main(){var p=P{1,2};var calls=0;p+=block{calls+=1;break P{3,4};};print(p.x," ",p.y," ",calls);}
