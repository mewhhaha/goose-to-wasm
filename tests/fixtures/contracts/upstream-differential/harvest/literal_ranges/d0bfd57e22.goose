recursive fn stencil(xs:u8[:])->i64 {
    var total=0;
    for dy in -1..2 {
        for dx,index in -1..2 {
            if dx==0 && dy==0 { continue; }
            if dy==1 && dx==1 { break; }
            let position=(dy+1)*3+dx+1;
            total+=xs[position]+index;
        }
    }
    return total;
}
recursive fn choose(seed:i64)->i64 {
    var total=seed;
    for value,index in -2..3 {
        let observed=value*10+index;
        if value == -1 { continue; }
        if value==1 { return total+observed; }
        total+=observed;
    }
    return total;
}
fn main() { let values:u8[9]=[1,2,3,4,5,6,7,8,9]; print(stencil(values[..])," ",choose(100)); }
