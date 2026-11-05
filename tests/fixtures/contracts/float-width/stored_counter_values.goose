fn bare(n:i64){var s:f32=0.5;var d:f64=0.25;block{if n==0{break s;}if n==1{break 0.1;}d}}fn main(){let f:f32=0.1;let widened=f as f64;print(bare(1)==widened," ",widened," ",bare(1));}
