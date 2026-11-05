fn apply<F>(){F();}fn main(){var n=41;var opt:i64?=n;fn use(){print(opt+1);}if opt{apply(use);}opt .= null;apply(use);}
