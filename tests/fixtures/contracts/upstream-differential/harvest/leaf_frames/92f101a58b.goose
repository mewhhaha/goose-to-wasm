struct Fixed { values:i64[2] }
struct Links { value:i64& }
recursive fn replace(var dst:Fixed&,src:Fixed&) { dst=src; }
recursive fn by_value(value:Fixed)->i64 { value.values[0] }
recursive fn embedded(links:Links&)->i64 { links.value }
recursive fn alias(value:i64)->i64 { let kept:i64& = value; kept+=2; return kept; }
recursive fn local_array(n:i64)->i64 { var values=[n,n+1]; return values[0]; }
fn main() {
    var a=Fixed {[1,2]}; var b=Fixed {[7,8]}; var value=10; var links=Links {value};
    replace(a,b); print(a.values[0]," ",by_value(a)," ",embedded(links)," ",alias(3)," ",local_array(5));
}
