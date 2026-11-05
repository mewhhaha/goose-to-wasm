const N:f32=-0.1;const P:f32=0.1;const NW:f64=N;let PW:f64=P;var VN:f64=N;
fn wide(x:f64)->f64{x}
fn main(){const local:f32=-0.1;let implicit:f64=local;const typed:f64=local;print(NW," ",PW," ",VN," ",implicit," ",typed);print(wide(N)," ",(if true{N}else{P}) as f64," ",wide(if false{P}else{N}));var flags:bool[>..]=[true,false];for c in flags{let v:f64=if c{local}else{P};print(v);}}
