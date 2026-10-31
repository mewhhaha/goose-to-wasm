enum E{None{pad},Zero{pad 0},Bytes{pad 3},Data{v:u16,pad 2}}
fn pick(p:E.None)->i64{return 1;}
fn pick(p:E.Zero)->i64{return 2;}
fn pick(p:E.Bytes)->i64{return 3;}
fn pick(p:E.Data)->i64{return p.v;}
recursive fn make()->E.Zero{return E.Zero{};}
fn main(){
    let a:E=E.None{};print(pick(a));
    let b:E..=E.Zero{};print(pick(b));
    let c:E..=E.Bytes{};print(pick(c));
    let d:E..=make();print(match d{Zero p=>4,_=>0});
    let fixed:E=c;print(pick(fixed));
    let data:E..=E.Data{17};print(pick(data));
}
