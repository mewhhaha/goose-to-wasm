fn main(){var xs=[1,2];let s:i64[:];s .= xs[..];s[1]=9;assert(xs[1]==9);print(s);}
