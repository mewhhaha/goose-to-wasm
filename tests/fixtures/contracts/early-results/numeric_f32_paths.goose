fn take(x:f32,want:f64)->bool{let wide:f64=x;wide==want}
fn choose(c:bool)->f32{block{if c{break 0.1;}break 0.2;}}
fn wide(x:f64)->bool{x==0.10000000149011612}
fn main(){print(take(block{break 0.1;},0.10000000149011612));print(take(block{break block{break 0.1;};},0.10000000149011612));var stored:f32=0.1;print(wide(block{break stored;}));print(take(choose(true),0.10000000149011612)," ",take(choose(false),0.20000000298023224));}
