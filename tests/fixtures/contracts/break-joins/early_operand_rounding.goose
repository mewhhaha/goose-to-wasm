fn main(){var fs:bool[>..]=[true,false];var n:i32=9;var s:f32=0.5;for c in fs{let a=(block{if c{break n*0.1;}0.25})*s;let b=(loop{if c{break n*0.1;}break 0.25;})*s;print(a," ",b);}}
