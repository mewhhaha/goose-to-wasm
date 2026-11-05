fn range_unsigned_012_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break 1;}break b;}}
fn range_unsigned_012_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break 1;}b}}
fn range_unsigned_012_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{1}else{b}}}
fn range_unsigned_021_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break b;}break 1;}}
fn range_unsigned_021_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break b;}1}}
fn range_unsigned_021_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{b}else{1}}}
fn range_unsigned_102_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break 300;}break b;}}
fn range_unsigned_102_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 300;}b}}
fn range_unsigned_102_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{300}else{b}}}
fn range_unsigned_120_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break b;}300}}
fn range_unsigned_120_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{b}else{300}}}
fn range_unsigned_201_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{300}else{1}}}
fn range_unsigned_210_early(n:i64){let b:u8=8;block{if n==0{break b;}if n==1{break 1;}300}}
fn range_unsigned_210_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{1}else{300}}}
fn range_fits_012_loop(n:i64){let b:u8=8;loop{if n==0{break 3;}if n==1{break 1;}break b;}}
fn range_fits_012_early(n:i64){let b:u8=8;block{if n==0{break 3;}if n==1{break 1;}b}}
fn range_fits_012_if(n:i64){let b:u8=8;if n==0{3}else{if n==1{1}else{b}}}
fn range_fits_021_loop(n:i64){let b:u8=8;loop{if n==0{break 3;}if n==1{break b;}break 1;}}
fn range_fits_021_early(n:i64){let b:u8=8;block{if n==0{break 3;}if n==1{break b;}1}}
fn range_fits_021_if(n:i64){let b:u8=8;if n==0{3}else{if n==1{b}else{1}}}
fn range_fits_102_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break 3;}break b;}}
fn range_fits_102_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 3;}b}}
fn range_fits_102_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{3}else{b}}}
fn range_fits_120_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break b;}break 3;}}
fn range_fits_120_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break b;}3}}
fn range_fits_120_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{b}else{3}}}
fn range_fits_201_loop(n:i64){let b:u8=8;loop{if n==0{break b;}if n==1{break 3;}break 1;}}
fn range_fits_201_early(n:i64){let b:u8=8;block{if n==0{break b;}if n==1{break 3;}1}}
fn range_fits_201_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{3}else{1}}}
fn range_fits_210_loop(n:i64){let b:u8=8;loop{if n==0{break b;}if n==1{break 1;}break 3;}}
fn range_fits_210_early(n:i64){let b:u8=8;block{if n==0{break b;}if n==1{break 1;}3}}
fn range_fits_210_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{1}else{3}}}
fn range_unsigned4_0123_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break 1;}if n==2{break 2;}break b;}}
fn range_unsigned4_0123_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break 1;}if n==2{break 2;}b}}
fn range_unsigned4_0123_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{1}else{if n==2{2}else{b}}}}
fn range_unsigned4_0132_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break 1;}if n==2{break b;}break 2;}}
fn range_unsigned4_0132_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break 1;}if n==2{break b;}2}}
fn range_unsigned4_0132_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{1}else{if n==2{b}else{2}}}}
fn range_unsigned4_0213_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break 2;}if n==2{break 1;}break b;}}
fn range_unsigned4_0213_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break 2;}if n==2{break 1;}b}}
fn range_unsigned4_0213_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{2}else{if n==2{1}else{b}}}}
fn range_unsigned4_0231_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break 2;}if n==2{break b;}break 1;}}
fn range_unsigned4_0231_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break 2;}if n==2{break b;}1}}
fn range_unsigned4_0231_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{2}else{if n==2{b}else{1}}}}
fn range_unsigned4_0312_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break b;}if n==2{break 1;}break 2;}}
fn range_unsigned4_0312_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break b;}if n==2{break 1;}2}}
fn range_unsigned4_0312_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{b}else{if n==2{1}else{2}}}}
fn range_unsigned4_0321_loop(n:i64){let b:u8=8;loop{if n==0{break 300;}if n==1{break b;}if n==2{break 2;}break 1;}}
fn range_unsigned4_0321_early(n:i64){let b:u8=8;block{if n==0{break 300;}if n==1{break b;}if n==2{break 2;}1}}
fn range_unsigned4_0321_if(n:i64){let b:u8=8;if n==0{300}else{if n==1{b}else{if n==2{2}else{1}}}}
fn range_unsigned4_1023_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break 300;}if n==2{break 2;}break b;}}
fn range_unsigned4_1023_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 300;}if n==2{break 2;}b}}
fn range_unsigned4_1023_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{300}else{if n==2{2}else{b}}}}
fn range_unsigned4_1032_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break 300;}if n==2{break b;}break 2;}}
fn range_unsigned4_1032_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 300;}if n==2{break b;}2}}
fn range_unsigned4_1032_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{300}else{if n==2{b}else{2}}}}
fn range_unsigned4_1203_loop(n:i64){let b:u8=8;loop{if n==0{break 1;}if n==1{break 2;}if n==2{break 300;}break b;}}
fn range_unsigned4_1203_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 2;}if n==2{break 300;}b}}
fn range_unsigned4_1203_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{2}else{if n==2{300}else{b}}}}
fn range_unsigned4_1230_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break 2;}if n==2{break b;}300}}
fn range_unsigned4_1230_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{2}else{if n==2{b}else{300}}}}
fn range_unsigned4_1302_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{b}else{if n==2{300}else{2}}}}
fn range_unsigned4_1320_early(n:i64){let b:u8=8;block{if n==0{break 1;}if n==1{break b;}if n==2{break 2;}300}}
fn range_unsigned4_1320_if(n:i64){let b:u8=8;if n==0{1}else{if n==1{b}else{if n==2{2}else{300}}}}
fn range_unsigned4_2013_loop(n:i64){let b:u8=8;loop{if n==0{break 2;}if n==1{break 300;}if n==2{break 1;}break b;}}
fn range_unsigned4_2013_early(n:i64){let b:u8=8;block{if n==0{break 2;}if n==1{break 300;}if n==2{break 1;}b}}
fn range_unsigned4_2013_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{300}else{if n==2{1}else{b}}}}
fn range_unsigned4_2031_loop(n:i64){let b:u8=8;loop{if n==0{break 2;}if n==1{break 300;}if n==2{break b;}break 1;}}
fn range_unsigned4_2031_early(n:i64){let b:u8=8;block{if n==0{break 2;}if n==1{break 300;}if n==2{break b;}1}}
fn range_unsigned4_2031_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{300}else{if n==2{b}else{1}}}}
fn range_unsigned4_2103_loop(n:i64){let b:u8=8;loop{if n==0{break 2;}if n==1{break 1;}if n==2{break 300;}break b;}}
fn range_unsigned4_2103_early(n:i64){let b:u8=8;block{if n==0{break 2;}if n==1{break 1;}if n==2{break 300;}b}}
fn range_unsigned4_2103_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{1}else{if n==2{300}else{b}}}}
fn range_unsigned4_2130_early(n:i64){let b:u8=8;block{if n==0{break 2;}if n==1{break 1;}if n==2{break b;}300}}
fn range_unsigned4_2130_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{1}else{if n==2{b}else{300}}}}
fn range_unsigned4_2301_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{b}else{if n==2{300}else{1}}}}
fn range_unsigned4_2310_early(n:i64){let b:u8=8;block{if n==0{break 2;}if n==1{break b;}if n==2{break 1;}300}}
fn range_unsigned4_2310_if(n:i64){let b:u8=8;if n==0{2}else{if n==1{b}else{if n==2{1}else{300}}}}
fn range_unsigned4_3012_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{300}else{if n==2{1}else{2}}}}
fn range_unsigned4_3021_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{300}else{if n==2{2}else{1}}}}
fn range_unsigned4_3102_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{1}else{if n==2{300}else{2}}}}
fn range_unsigned4_3120_early(n:i64){let b:u8=8;block{if n==0{break b;}if n==1{break 1;}if n==2{break 2;}300}}
fn range_unsigned4_3120_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{1}else{if n==2{2}else{300}}}}
fn range_unsigned4_3201_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{2}else{if n==2{300}else{1}}}}
fn range_unsigned4_3210_early(n:i64){let b:u8=8;block{if n==0{break b;}if n==1{break 2;}if n==2{break 1;}300}}
fn range_unsigned4_3210_if(n:i64){let b:u8=8;if n==0{b}else{if n==1{2}else{if n==2{1}else{300}}}}
fn range_nested_loop(n:i64){let b:u8=8;loop{if n<2{break loop{if n==0{break 300;}break 1;};}break b;}}
fn range_nested_early(n:i64){let b:u8=8;block{if n<2{break block{if n==0{break 300;}1};}b}}
fn range_nested_if(n:i64){let b:u8=8;if n<2{if n==0{300}else{1}}else{b}}
fn range_nested_nested_targets(n:i64){let b:u8=8;loop{let inner=loop{break 9;};fn unrelated(){loop{break 0.25;}}if n==0{break 300;}if n==1{break 1;}if inner==9{break b;}break 2;}}
fn range_inferred_if(n:i64){if n>=0{block{let b:u8=8;if n==0{break 300;}if n==1{break 1;}b}}else{0}}
fn range_inferred_match(n:i64){match n{_=>block{let b:u8=8;if n==0{break 300;}if n==1{break 1;}b}}}
fn range_explicit_return(n:i64){return block{let b:u8=8;if n==0{break 300;}if n==1{break 1;}b};}
fn main(){
print(range_unsigned_012_loop(0)," ",range_unsigned_012_loop(1)," ",range_unsigned_012_loop(2));
print(range_unsigned_012_early(0)," ",range_unsigned_012_early(1)," ",range_unsigned_012_early(2));
print(range_unsigned_012_if(0)," ",range_unsigned_012_if(1)," ",range_unsigned_012_if(2));
print(range_unsigned_021_loop(0)," ",range_unsigned_021_loop(1)," ",range_unsigned_021_loop(2));
print(range_unsigned_021_early(0)," ",range_unsigned_021_early(1)," ",range_unsigned_021_early(2));
print(range_unsigned_021_if(0)," ",range_unsigned_021_if(1)," ",range_unsigned_021_if(2));
print(range_unsigned_102_loop(0)," ",range_unsigned_102_loop(1)," ",range_unsigned_102_loop(2));
print(range_unsigned_102_early(0)," ",range_unsigned_102_early(1)," ",range_unsigned_102_early(2));
print(range_unsigned_102_if(0)," ",range_unsigned_102_if(1)," ",range_unsigned_102_if(2));
print(range_unsigned_120_early(0)," ",range_unsigned_120_early(1)," ",range_unsigned_120_early(2));
print(range_unsigned_120_if(0)," ",range_unsigned_120_if(1)," ",range_unsigned_120_if(2));
print(range_unsigned_201_if(0)," ",range_unsigned_201_if(1)," ",range_unsigned_201_if(2));
print(range_unsigned_210_early(0)," ",range_unsigned_210_early(1)," ",range_unsigned_210_early(2));
print(range_unsigned_210_if(0)," ",range_unsigned_210_if(1)," ",range_unsigned_210_if(2));
print(range_fits_012_loop(0)," ",range_fits_012_loop(1)," ",range_fits_012_loop(2));
print(range_fits_012_early(0)," ",range_fits_012_early(1)," ",range_fits_012_early(2));
print(range_fits_012_if(0)," ",range_fits_012_if(1)," ",range_fits_012_if(2));
print(range_fits_021_loop(0)," ",range_fits_021_loop(1)," ",range_fits_021_loop(2));
print(range_fits_021_early(0)," ",range_fits_021_early(1)," ",range_fits_021_early(2));
print(range_fits_021_if(0)," ",range_fits_021_if(1)," ",range_fits_021_if(2));
print(range_fits_102_loop(0)," ",range_fits_102_loop(1)," ",range_fits_102_loop(2));
print(range_fits_102_early(0)," ",range_fits_102_early(1)," ",range_fits_102_early(2));
print(range_fits_102_if(0)," ",range_fits_102_if(1)," ",range_fits_102_if(2));
print(range_fits_120_loop(0)," ",range_fits_120_loop(1)," ",range_fits_120_loop(2));
print(range_fits_120_early(0)," ",range_fits_120_early(1)," ",range_fits_120_early(2));
print(range_fits_120_if(0)," ",range_fits_120_if(1)," ",range_fits_120_if(2));
print(range_fits_201_loop(0)," ",range_fits_201_loop(1)," ",range_fits_201_loop(2));
print(range_fits_201_early(0)," ",range_fits_201_early(1)," ",range_fits_201_early(2));
print(range_fits_201_if(0)," ",range_fits_201_if(1)," ",range_fits_201_if(2));
print(range_fits_210_loop(0)," ",range_fits_210_loop(1)," ",range_fits_210_loop(2));
print(range_fits_210_early(0)," ",range_fits_210_early(1)," ",range_fits_210_early(2));
print(range_fits_210_if(0)," ",range_fits_210_if(1)," ",range_fits_210_if(2));
print(range_unsigned4_0123_loop(0)," ",range_unsigned4_0123_loop(1)," ",range_unsigned4_0123_loop(2)," ",range_unsigned4_0123_loop(3));
print(range_unsigned4_0123_early(0)," ",range_unsigned4_0123_early(1)," ",range_unsigned4_0123_early(2)," ",range_unsigned4_0123_early(3));
print(range_unsigned4_0123_if(0)," ",range_unsigned4_0123_if(1)," ",range_unsigned4_0123_if(2)," ",range_unsigned4_0123_if(3));
print(range_unsigned4_0132_loop(0)," ",range_unsigned4_0132_loop(1)," ",range_unsigned4_0132_loop(2)," ",range_unsigned4_0132_loop(3));
print(range_unsigned4_0132_early(0)," ",range_unsigned4_0132_early(1)," ",range_unsigned4_0132_early(2)," ",range_unsigned4_0132_early(3));
print(range_unsigned4_0132_if(0)," ",range_unsigned4_0132_if(1)," ",range_unsigned4_0132_if(2)," ",range_unsigned4_0132_if(3));
print(range_unsigned4_0213_loop(0)," ",range_unsigned4_0213_loop(1)," ",range_unsigned4_0213_loop(2)," ",range_unsigned4_0213_loop(3));
print(range_unsigned4_0213_early(0)," ",range_unsigned4_0213_early(1)," ",range_unsigned4_0213_early(2)," ",range_unsigned4_0213_early(3));
print(range_unsigned4_0213_if(0)," ",range_unsigned4_0213_if(1)," ",range_unsigned4_0213_if(2)," ",range_unsigned4_0213_if(3));
print(range_unsigned4_0231_loop(0)," ",range_unsigned4_0231_loop(1)," ",range_unsigned4_0231_loop(2)," ",range_unsigned4_0231_loop(3));
print(range_unsigned4_0231_early(0)," ",range_unsigned4_0231_early(1)," ",range_unsigned4_0231_early(2)," ",range_unsigned4_0231_early(3));
print(range_unsigned4_0231_if(0)," ",range_unsigned4_0231_if(1)," ",range_unsigned4_0231_if(2)," ",range_unsigned4_0231_if(3));
print(range_unsigned4_0312_loop(0)," ",range_unsigned4_0312_loop(1)," ",range_unsigned4_0312_loop(2)," ",range_unsigned4_0312_loop(3));
print(range_unsigned4_0312_early(0)," ",range_unsigned4_0312_early(1)," ",range_unsigned4_0312_early(2)," ",range_unsigned4_0312_early(3));
print(range_unsigned4_0312_if(0)," ",range_unsigned4_0312_if(1)," ",range_unsigned4_0312_if(2)," ",range_unsigned4_0312_if(3));
print(range_unsigned4_0321_loop(0)," ",range_unsigned4_0321_loop(1)," ",range_unsigned4_0321_loop(2)," ",range_unsigned4_0321_loop(3));
print(range_unsigned4_0321_early(0)," ",range_unsigned4_0321_early(1)," ",range_unsigned4_0321_early(2)," ",range_unsigned4_0321_early(3));
print(range_unsigned4_0321_if(0)," ",range_unsigned4_0321_if(1)," ",range_unsigned4_0321_if(2)," ",range_unsigned4_0321_if(3));
print(range_unsigned4_1023_loop(0)," ",range_unsigned4_1023_loop(1)," ",range_unsigned4_1023_loop(2)," ",range_unsigned4_1023_loop(3));
print(range_unsigned4_1023_early(0)," ",range_unsigned4_1023_early(1)," ",range_unsigned4_1023_early(2)," ",range_unsigned4_1023_early(3));
print(range_unsigned4_1023_if(0)," ",range_unsigned4_1023_if(1)," ",range_unsigned4_1023_if(2)," ",range_unsigned4_1023_if(3));
print(range_unsigned4_1032_loop(0)," ",range_unsigned4_1032_loop(1)," ",range_unsigned4_1032_loop(2)," ",range_unsigned4_1032_loop(3));
print(range_unsigned4_1032_early(0)," ",range_unsigned4_1032_early(1)," ",range_unsigned4_1032_early(2)," ",range_unsigned4_1032_early(3));
print(range_unsigned4_1032_if(0)," ",range_unsigned4_1032_if(1)," ",range_unsigned4_1032_if(2)," ",range_unsigned4_1032_if(3));
print(range_unsigned4_1203_loop(0)," ",range_unsigned4_1203_loop(1)," ",range_unsigned4_1203_loop(2)," ",range_unsigned4_1203_loop(3));
print(range_unsigned4_1203_early(0)," ",range_unsigned4_1203_early(1)," ",range_unsigned4_1203_early(2)," ",range_unsigned4_1203_early(3));
print(range_unsigned4_1203_if(0)," ",range_unsigned4_1203_if(1)," ",range_unsigned4_1203_if(2)," ",range_unsigned4_1203_if(3));
print(range_unsigned4_1230_early(0)," ",range_unsigned4_1230_early(1)," ",range_unsigned4_1230_early(2)," ",range_unsigned4_1230_early(3));
print(range_unsigned4_1230_if(0)," ",range_unsigned4_1230_if(1)," ",range_unsigned4_1230_if(2)," ",range_unsigned4_1230_if(3));
print(range_unsigned4_1302_if(0)," ",range_unsigned4_1302_if(1)," ",range_unsigned4_1302_if(2)," ",range_unsigned4_1302_if(3));
print(range_unsigned4_1320_early(0)," ",range_unsigned4_1320_early(1)," ",range_unsigned4_1320_early(2)," ",range_unsigned4_1320_early(3));
print(range_unsigned4_1320_if(0)," ",range_unsigned4_1320_if(1)," ",range_unsigned4_1320_if(2)," ",range_unsigned4_1320_if(3));
print(range_unsigned4_2013_loop(0)," ",range_unsigned4_2013_loop(1)," ",range_unsigned4_2013_loop(2)," ",range_unsigned4_2013_loop(3));
print(range_unsigned4_2013_early(0)," ",range_unsigned4_2013_early(1)," ",range_unsigned4_2013_early(2)," ",range_unsigned4_2013_early(3));
print(range_unsigned4_2013_if(0)," ",range_unsigned4_2013_if(1)," ",range_unsigned4_2013_if(2)," ",range_unsigned4_2013_if(3));
print(range_unsigned4_2031_loop(0)," ",range_unsigned4_2031_loop(1)," ",range_unsigned4_2031_loop(2)," ",range_unsigned4_2031_loop(3));
print(range_unsigned4_2031_early(0)," ",range_unsigned4_2031_early(1)," ",range_unsigned4_2031_early(2)," ",range_unsigned4_2031_early(3));
print(range_unsigned4_2031_if(0)," ",range_unsigned4_2031_if(1)," ",range_unsigned4_2031_if(2)," ",range_unsigned4_2031_if(3));
print(range_unsigned4_2103_loop(0)," ",range_unsigned4_2103_loop(1)," ",range_unsigned4_2103_loop(2)," ",range_unsigned4_2103_loop(3));
print(range_unsigned4_2103_early(0)," ",range_unsigned4_2103_early(1)," ",range_unsigned4_2103_early(2)," ",range_unsigned4_2103_early(3));
print(range_unsigned4_2103_if(0)," ",range_unsigned4_2103_if(1)," ",range_unsigned4_2103_if(2)," ",range_unsigned4_2103_if(3));
print(range_unsigned4_2130_early(0)," ",range_unsigned4_2130_early(1)," ",range_unsigned4_2130_early(2)," ",range_unsigned4_2130_early(3));
print(range_unsigned4_2130_if(0)," ",range_unsigned4_2130_if(1)," ",range_unsigned4_2130_if(2)," ",range_unsigned4_2130_if(3));
print(range_unsigned4_2301_if(0)," ",range_unsigned4_2301_if(1)," ",range_unsigned4_2301_if(2)," ",range_unsigned4_2301_if(3));
print(range_unsigned4_2310_early(0)," ",range_unsigned4_2310_early(1)," ",range_unsigned4_2310_early(2)," ",range_unsigned4_2310_early(3));
print(range_unsigned4_2310_if(0)," ",range_unsigned4_2310_if(1)," ",range_unsigned4_2310_if(2)," ",range_unsigned4_2310_if(3));
print(range_unsigned4_3012_if(0)," ",range_unsigned4_3012_if(1)," ",range_unsigned4_3012_if(2)," ",range_unsigned4_3012_if(3));
print(range_unsigned4_3021_if(0)," ",range_unsigned4_3021_if(1)," ",range_unsigned4_3021_if(2)," ",range_unsigned4_3021_if(3));
print(range_unsigned4_3102_if(0)," ",range_unsigned4_3102_if(1)," ",range_unsigned4_3102_if(2)," ",range_unsigned4_3102_if(3));
print(range_unsigned4_3120_early(0)," ",range_unsigned4_3120_early(1)," ",range_unsigned4_3120_early(2)," ",range_unsigned4_3120_early(3));
print(range_unsigned4_3120_if(0)," ",range_unsigned4_3120_if(1)," ",range_unsigned4_3120_if(2)," ",range_unsigned4_3120_if(3));
print(range_unsigned4_3201_if(0)," ",range_unsigned4_3201_if(1)," ",range_unsigned4_3201_if(2)," ",range_unsigned4_3201_if(3));
print(range_unsigned4_3210_early(0)," ",range_unsigned4_3210_early(1)," ",range_unsigned4_3210_early(2)," ",range_unsigned4_3210_early(3));
print(range_unsigned4_3210_if(0)," ",range_unsigned4_3210_if(1)," ",range_unsigned4_3210_if(2)," ",range_unsigned4_3210_if(3));
print(range_nested_loop(0)," ",range_nested_loop(1)," ",range_nested_loop(2));
print(range_nested_early(0)," ",range_nested_early(1)," ",range_nested_early(2));
print(range_nested_if(0)," ",range_nested_if(1)," ",range_nested_if(2));
print(range_nested_nested_targets(0)," ",range_nested_nested_targets(1)," ",range_nested_nested_targets(2));
print(range_inferred_if(0)," ",range_inferred_if(1)," ",range_inferred_if(2));
print(range_inferred_match(0)," ",range_inferred_match(1)," ",range_inferred_match(2));
print(range_explicit_return(0)," ",range_explicit_return(1)," ",range_explicit_return(2));
}
