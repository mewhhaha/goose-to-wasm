struct N{v:i64}var nodes:N[>..]=[N{7}];var other:N[>..]=[N{8}];fn main(){let r:N&<u32 in nodes>?;r .= &other[0];print(r);}
