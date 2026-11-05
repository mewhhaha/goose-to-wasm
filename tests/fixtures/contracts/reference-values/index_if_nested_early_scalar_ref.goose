fn main(){var a:i64[>..]=[10,20];let c=a.len>1;print(a.index_of(if c { block { break &a[0]; } } else { &a[1] }));}
