var a:varint[>..]=[64];
fn apply<F>(){a.append(F());}
recursive fn values<F>()->varint[u8]{return[1,F(),8192];}
fn target(flag:bool)->i64{apply(){values(){if flag{return 7;}else{-65}}};return 0;}
fn main(){
    print(target(true));a.push(9);print(a);
    a.clear();a.push(64);print(target(false));print(a);
}
