var calls=0;recursive fn mark()->i64{calls++;print("fill ",calls);return -65;}fn main(){var a:varint[>..]=[64];a.append([mark();0]);a.append([mark();3]);print(a," ",calls);}
