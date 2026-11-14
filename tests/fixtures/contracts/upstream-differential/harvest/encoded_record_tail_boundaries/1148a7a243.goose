enum E{Empty,Data{tag:u8,values:varint[varint]}}fn main(){let e:E..=E.Data{1,[7;128]};
match e{Data p=>print(p.values.len),_=>{}}}