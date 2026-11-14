recursive fn changed(a:i64,var b:i64)->i64 { b++; return a%b; }
recursive fn addressed(a:i64,var b:i64)->i64 { let alias:i64& = b; alias++; return a%b; }
recursive fn captured(a:i64,var b:i64)->i64 { recursive fn bump() { b++; } bump(); return a%b; }
recursive fn observe()->i64 { var values:i64[>..]=[0]; return values[0]; }
recursive fn called(a:i64,b:i64)->i64 { let side=observe(); return a%b+side; }
recursive fn shadowed(a:i64,b:i64)->i64 { { var b=3; b++; } return a%b; }
recursive fn narrow(a:i32,b:i32)->i32 { a%b }
recursive fn large(var a:i64,b:i64)->i64 {a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;a+=1;return a%b;}fn main() {
    print(changed(-17,8)," ",addressed(-17,8)," ",captured(-17,8)," ",called(-17,8));
    print(shadowed(-17,8)," ",narrow(-17,8)," ",large(-17,8));
}