struct P{x:i64,y:i64}
fn update(p:P&,c:bool){p+=block{if c{break P{3,4};}exit(0);};}
fn main(){var p=P{1,2};update(p,true);print(p.x," ",p.y);}
