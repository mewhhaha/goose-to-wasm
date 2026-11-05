struct N{v:i64}var nodes:N[>..]=[N{7}];fn main(){let r:N&<u32 in nodes>?;r .= &nodes[0];if r{print(r.v);}}
