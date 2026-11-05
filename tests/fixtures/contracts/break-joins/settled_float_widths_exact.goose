fn bare(n:i64){var s:f32=0.5;var d:f64=0.25;block{if n==0{break s;}if n==1{break 0.1;}d}}
fn negative(n:i64){var s:f32=-0.5;var d:f64=-0.25;block{if n==0{break s;}if n==1{break -0.1;}d}}
fn conditional(n:i64){var s:f32=0.5;var d:f64=0.25;var c:bool=true;block{if n==0{break s;}if n==1{break if c{0.1}else{0.2};}d}}
fn nested(n:i64){var s:f32=0.5;var d:f64=0.25;var c:bool=true;block{if n==0{break s;}if n==1{break block{if c{break 0.1;}0.2};}d}}
fn reversed(n:i64){var s:f32=0.5;var d:f64=0.25;block{if n==0{break 0.1;}if n==1{break s;}d}}
fn loop_value(n:i64){var s:f32=0.5;var d:f64=0.25;var c:bool=true;block{if n==0{break s;}if n==1{break loop{if c{break 0.1;}break 0.2;};}d}}
fn main(){let widened:f64=0.10000000149011612;let negative_widened:f64=-0.10000000149011612;print(bare(1)==widened," ",negative(1)==negative_widened," ",conditional(1)==widened," ",nested(1)==widened," ",loop_value(1)==widened);print(bare(1)," ",negative(1)," ",conditional(1)," ",nested(1)," ",loop_value(1));print(reversed(0));}
