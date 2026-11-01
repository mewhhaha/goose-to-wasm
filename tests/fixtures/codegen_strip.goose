extern fn bench_input() -> i64;

recursive fn three(xs:u32[:],seed:u32) {
    var lanes:u32[3]=[seed;3]; var total:u32=seed;
    for value,i in xs {
        let lane=i%3;
        let mixed=value+(i as! u32);
        lanes[lane]^=mixed;
        total+=lanes[lane];
    }
    print(lanes," ",total);
}
recursive fn eight(xs:u32[:],seed:u32) {
    var lanes:u32[8]=[seed;8]; var total:u32=seed;
    for value,i in xs {
        let lane=i%8;
        let mixed=value+(i as! u32);
        lanes[lane]^=mixed;
        total+=lanes[lane];
    }
    print(lanes," ",total);
}
recursive fn signed_lanes(xs:u32[:]) {
    var lanes:i32[3]=[-11,7,31];
    var total:i64=0;
    for value,i in xs {
        let lane=i%3;
        let before=lanes[lane];
        lanes[lane]+=((value&31) as! i32);
        lanes[lane]^=before;
        lanes[lane]++;
        lanes[lane]=lanes[lane]-(i as! i32);
        total+=lanes[lane];
    }
    print(lanes," ",total);
}
recursive fn wide_lanes(xs:u32[:]) {
    var lanes:u64[8]=[0xFFFFFFFFFFFFFFF0;8];
    for value,i in xs {
        let before=lanes[i%8];
        lanes[i%8]+=(value as u64);
        lanes[i%8]^=before;
        lanes[i%8]++;
        lanes[i%8]=lanes[i%8]+(i as u64);
    }
    print(lanes);
}
var calls=0;
recursive fn observe(value:u32)->u32 { calls++; return value; }
recursive fn fallbacks(xs:u32[:]) {
    var called:u32=0;
    for value,i in xs { called+=observe(value)+((i%3) as! u32); }
    var exited:u32=0;
    for value,i in xs {
        if i==1 { continue; }
        if i==5 { break; }
        exited+=value+((i%3) as! u32);
    }
    var captured:u32=0;
    for value,i in xs {
        recursive fn read()->u32 { return value+((i%3) as! u32); }
        captured+=read();
    }
    var addressed:u32=0;
    for value,i in xs {
        var copy=value;
        let link:u32& = copy;
        link+=((i%3) as! u32);
        addressed+=link;
    }
    print(called," ",calls," ",exited," ",captured," ",addressed);
    let first:u32[4]=[2,3,5,7]; let second:u32[2]=[13,17];
    var view:u32[:]=first[..]; var rebound:u32=0;
    for value,i in view {
        rebound+=value+((i%3) as! u32);
        if i==0 { view=second[..]; }
    }
    print(rebound);
}
fn main() {
    let count=bench_input(); let seed=bench_input() as! u32;
    var data:u32[17]=[0;17];
    for i in 17 { data[i]=seed+(i as! u32)*37; }
    let xs=data[..count];
    three(xs,seed); eight(xs,seed); signed_lanes(xs); wide_lanes(xs); fallbacks(xs);
}
