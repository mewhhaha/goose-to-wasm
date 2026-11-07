fn take(x:i64&){x+=1;}fn main(){var a=1;take(block{break a;});print(a);}
