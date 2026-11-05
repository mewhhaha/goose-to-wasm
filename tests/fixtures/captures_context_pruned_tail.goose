fn stop(x:i64&){abort("unused");}fn stop(x:i64?){print("empty");}fn main(){var n=7;var opt:i64?=n;fn work(){stop(opt);print("tail");}if false{if opt{work();}}opt .= null;work();}
