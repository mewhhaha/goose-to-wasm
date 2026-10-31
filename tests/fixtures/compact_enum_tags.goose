enum E { Empty {}, Data { tag:u8,word:u16 } }
enum Flag { A {}, B }
struct Wrapped { lead:u8,value:E,after:u8 }
recursive fn make(n:i64)->E { if n > 0 { return E.Data{7,300}; } return E.Empty{}; }
recursive fn variable(n:i64)->E.. { if n > 0 { return E.Data{8,400}; } return E.Empty{}; }
recursive fn empty()->Flag.A { return Flag.A{}; }
fn main() {
    let a=Wrapped{0x11,make(1),0x22};
    let b=Wrapped{0x33,make(0),0x44};
    let av=match a.value { Data p=>p.tag as i64+p.word as i64, _=>-1 };
    let bv=match b.value { Empty p=>5, _=>-1 };
    print(a.lead as i64," ",av," ",a.after as i64," ",b.lead as i64," ",bv," ",b.after as i64);
    var x=variable(1); var y=variable(0);
    let xv=match x { Data &p=>p.tag as i64+p.word as i64, _=>-1 };
    let yv=match y { Empty &p=>6, _=>-1 };
    print(xv," ",yv);
    let flags:Flag[3]=[empty(),Flag.B,Flag.A{}];
    print(match flags[0] { A p=>1, _=>-1 }," ",match flags[1] { B=>2, _=>-1 });
}
