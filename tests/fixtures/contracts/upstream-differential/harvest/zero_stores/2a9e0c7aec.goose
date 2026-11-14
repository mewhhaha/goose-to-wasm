var calls=0;
recursive fn zero()->u16 { calls++; return 0; }
recursive fn image(clear:bool)->u16[4] { if clear { return [0;4]; } return [7;4]; }
struct Values { a:i8,b:u16,c:i32,d:u64,z:f64 }
fn main() {
    print(image(false)); print(image(true)); print(image(true));
    let filled:u16[4]=[zero();4]; print(filled," ",calls);
    print(Values {0,0,0,0,-0.0});
}