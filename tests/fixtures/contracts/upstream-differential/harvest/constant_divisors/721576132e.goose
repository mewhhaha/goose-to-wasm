export fn wrap(a:i64,w:i64,h:i64)->i64 { (a%w)*100+a%h }
fn main() {
    print(wrap(-17,12,8)); print(wrap(-17,64,32));
    print(wrap(-17,16,8)); print(wrap(-17,12,8));
}
